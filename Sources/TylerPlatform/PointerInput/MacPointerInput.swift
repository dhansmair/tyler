import AppKit
import TylerCore
import TylerRuntime
import TylerServer

/// The real `PointerInput`: reads the mouse button state from AppKit and watches the primary
/// button dragging and going up anywhere on screen through a global event monitor. Global monitors
/// only see events sent to other apps, which is every click that matters: tylerd has no windows
/// of its own, only the menu bar item. Trackpad swipes come from a `TrackpadGestureListener`,
/// moves from a `PointerMoveListener`, drags with the modifier or in a gap from a
/// `MouseButtonInterceptor`, which exists only while `PressTakeover` says a press may be tyler's:
/// while the `ModifierKeyListener` sees the modifier held, while tylerd says the pointer is over
/// a gap, and until a gesture's button comes up.
@MainActor
package final class MacPointerInput: PointerInput {
  private static let log = TylerLog(category: "pointer")

  package let events: AsyncStream<PointerEvent>

  private let continuation: AsyncStream<PointerEvent>.Continuation
  private var monitor: Any?
  private var tapCheck: Task<Void, Never>?
  private var gestureListener: TrackpadGestureListener?
  private var moveListener: PointerMoveListener?
  private var modifierListener: ModifierKeyListener?
  private var buttonInterceptor: MouseButtonInterceptor?
  private var takeover = PressTakeover(modifier: [], takesGaps: false)
  /// Whether the interceptor's last arming was refused, so a refusal is logged once, not at every
  /// press of the modifier.
  private var wasRefused = false
  private var turnedOff: [InputListener.Kind: TurnedOff] = [:]
  package var canCapture: (@MainActor (CGPoint, ModifierGesture.Kind) -> Bool)?

  package init() {
    (events, continuation) = AsyncStream.makeStream(of: PointerEvent.self)
  }

  package var isPrimaryButtonDown: Bool {
    NSEvent.pressedMouseButtons & 1 != 0
  }

  package func start() {
    guard monitor == nil else { return }
    // The first read of the window list in a process takes 20–40 ms (measured in the spike).
    // Paying it now keeps it out of the tap at the first press.
    _ = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
    // AppKit calls global monitors on the main thread, which is what makes `assumeIsolated` safe.
    let mask: NSEvent.EventTypeMask = [.leftMouseDragged, .leftMouseUp]
    monitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
      let isRelease = event.type == .leftMouseUp
      MainActor.assumeIsolated { self?.report(isRelease: isRelease) }
    }
    tapCheck = Task { [weak self] in
      while true {
        do { try await Task.sleep(for: .seconds(2)) } catch { return }
        self?.turnTapsBackOn()
      }
    }
  }

  package func stop() {
    watch(PointerWatch())
    takeover = PressTakeover(modifier: [], takesGaps: false)
    tapCheck?.cancel()
    tapCheck = nil
    guard let monitor else { return }
    NSEvent.removeMonitor(monitor)
    self.monitor = nil
  }

  package func watch(_ watch: PointerWatch) {
    watchSwipes(fingers: watch.swipeFingers)
    watchMoves(watch.moves)
    watchPresses(keys: watch.modifierKeys, gaps: watch.gapPresses)
  }

  private func watchSwipes(fingers: Int?) {
    guard fingers != gestureListener?.fingers else { return }
    gestureListener?.invalidate()
    gestureListener = nil
    guard let fingers else { return }
    gestureListener = TrackpadGestureListener(fingers: fingers) { [weak self] update in
      guard let self else { return }
      continuation.yield(.swipe(update, location: pointerLocation()))
    }
  }

  package func gapHovered(_ isOverGap: Bool) {
    if takeover.gapHovered(isOverGap) { applyTakeover() }
  }

  private func watchPresses(keys: ModifierKeys, gaps: Bool) {
    // Kept while the settings stay the same, so a reload doesn't drop a gesture under way.
    guard keys != takeover.modifier || gaps != takeover.takesGaps else { return }
    disarm()
    watchModifier(keys)
    _ = takeover.configure(modifier: keys, takesGaps: gaps)
    _ = takeover.keysChanged(to: keys.isEmpty ? [] : ModifierKeyListener.keysHeld)
    applyTakeover()
  }

  private func watchModifier(_ keys: ModifierKeys) {
    guard keys.isEmpty != (modifierListener == nil) else { return }
    modifierListener?.invalidate()
    modifierListener = nil
    guard !keys.isEmpty else { return }
    modifierListener = ModifierKeyListener { [weak self] keys in
      guard let self, takeover.keysChanged(to: keys) else { return }
      applyTakeover()
    }
  }

  /// A gesture began or ended, reported from within the interceptor's tap: the interceptor is
  /// removed only once its callback has returned, so the event it is deciding on still goes
  /// where it said.
  private func gestureChanged(isActive: Bool) {
    guard takeover.gestureChanged(isActive: isActive) else { return }
    RunLoop.main.perform(inModes: [.common]) { [weak self] in
      MainActor.assumeIsolated { self?.applyTakeover() }
    }
  }

  private func applyTakeover() {
    if takeover.needsTap { arm() } else { disarm() }
  }

  private func arm() {
    guard buttonInterceptor == nil else { return }
    let canCapture: @MainActor (CGPoint, ModifierGesture.Kind) -> Bool = { [weak self] in
      self?.canCapture?($0, $1) ?? false
    }
    buttonInterceptor = MouseButtonInterceptor(
      keys: takeover.modifier, takesGaps: takeover.takesGaps, canCapture: canCapture,
      report: { [weak self] event in self?.continuation.yield(event) },
      gestureChanged: { [weak self] isActive in self?.gestureChanged(isActive: isActive) })
    if buttonInterceptor == nil {
      if !wasRefused {
        Self.log.error(
          "mouse button interceptor refused - moving windows with the modifier and resizing by"
            + " the gaps are off")
      }
      wasRefused = true
      return
    }
    wasRefused = false
    Self.log.debug("mouse button interceptor armed")
  }

  private func disarm() {
    guard let buttonInterceptor else { return }
    buttonInterceptor.invalidate()
    self.buttonInterceptor = nil
    Self.log.debug("mouse button interceptor disarmed")
  }

  private func watchMoves(_ isOn: Bool) {
    guard isOn != (moveListener != nil) else { return }
    moveListener?.invalidate()
    moveListener = nil
    guard isOn else { return }
    moveListener = PointerMoveListener { [weak self] location in
      self?.continuation.yield(.moved(location: location))
    }
  }

  /// macOS turns a tap off when its callback is slow, after a wake for one. It tells the callback,
  /// but seconds late, and a tap turned off again may never hear (measured; see "Events and taps"
  /// in `devdocs/macos-behaviour.md`), so the taps are checked here instead.
  private func turnTapsBackOn() {
    let turnedBackOn: [(InputListener.Kind, Bool?)] = [
      (.swipes, gestureListener?.turnBackOnIfOff()),
      (.pointerMoves, moveListener?.turnBackOnIfOff()),
      (.modifierKey, modifierListener?.turnBackOnIfOff()),
      (.mouseButtons, buttonInterceptor?.turnBackOnIfOff()),
    ]
    for case (let kind, true) in turnedBackOn {
      Self.log.warning("event listener turned back on - \(kind.rawValue) - macOS had turned it off")
      turnedOff[kind, default: TurnedOff()].count += 1
      turnedOff[kind]?.last = Date()
    }
  }

  package var listeners: [InputListener] {
    var listening: [(InputListener.Kind, Bool)] = []
    if let gestureListener { listening.append((.swipes, gestureListener.isListening)) }
    if let moveListener { listening.append((.pointerMoves, moveListener.isListening)) }
    if let modifierListener { listening.append((.modifierKey, modifierListener.isListening)) }
    // The interceptor exists only while a press may be tyler's, so it is listed while presses are
    // taken over at all.
    if !takeover.modifier.isEmpty || takeover.takesGaps {
      listening.append((.mouseButtons, !wasRefused))
    }
    return listening.map { kind, isListening in
      InputListener(
        kind: kind, isListening: isListening, timesTurnedOff: turnedOff[kind]?.count ?? 0,
        lastTurnedOff: turnedOff[kind]?.last)
    }
  }

  private struct TurnedOff {
    var count = 0
    var last: Date?
  }

  /// Reports a drag step or the release with where the pointer is, in Accessibility coordinates
  /// (top-left origin on the primary display).
  private func report(isRelease: Bool) {
    let location = pointerLocation()
    continuation.yield(
      isRelease
        ? .primaryButtonReleased(location: location) : .primaryButtonDragged(location: location))
  }

  /// Where the pointer is, in Accessibility coordinates (top-left origin on the primary display).
  private func pointerLocation() -> CGPoint {
    let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
    return DisplayGeometry.axRect(
      fromAppKit: CGRect(origin: NSEvent.mouseLocation, size: .zero),
      primaryScreenHeight: primaryHeight
    ).origin
  }
}
