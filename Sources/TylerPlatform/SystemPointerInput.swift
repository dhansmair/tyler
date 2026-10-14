import AppKit
import TylerCore
import TylerServer

/// The real `PointerInput`: reads the mouse button state from AppKit and watches the primary
/// button dragging and going up anywhere on screen through a global event monitor. Global monitors
/// only see events sent to other apps, which is every click that matters: tylerd has no windows
/// of its own, only the menu bar item. Trackpad swipes come from a `TrackpadGestureListener`,
/// moves from a `PointerMoveListener`, drags with the modifier or in a gap from a
/// `MouseButtonInterceptor`.
@MainActor
package final class SystemPointerInput: PointerInput {
  package let events: AsyncStream<PointerEvent>

  private let continuation: AsyncStream<PointerEvent>.Continuation
  private var monitor: Any?
  private var gestureListener: TrackpadGestureListener?
  private var moveListener: PointerMoveListener?
  private var buttonInterceptor: MouseButtonInterceptor?
  package var canCapture: (@MainActor (CGPoint, ModifierGesture.Kind) -> Bool)?

  package init() {
    (events, continuation) = AsyncStream.makeStream(of: PointerEvent.self)
  }

  package var isPrimaryButtonDown: Bool {
    NSEvent.pressedMouseButtons & 1 != 0
  }

  package func start() {
    guard monitor == nil else { return }
    // AppKit calls global monitors on the main thread, which is what makes `assumeIsolated` safe.
    let mask: NSEvent.EventTypeMask = [.leftMouseDragged, .leftMouseUp]
    monitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
      let isRelease = event.type == .leftMouseUp
      MainActor.assumeIsolated { self?.report(isRelease: isRelease) }
    }
  }

  package func stop() {
    watch(PointerWatch())
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

  private func watchPresses(keys: ModifierKeys, gaps: Bool) {
    // Kept while the settings stay the same, so a reload doesn't drop a gesture under way.
    guard keys != buttonInterceptor?.keys ?? [] || gaps != buttonInterceptor?.takesGaps ?? false
    else { return }
    removeButtonInterceptor()
    guard !keys.isEmpty || gaps else { return }
    let canCapture: @MainActor (CGPoint, ModifierGesture.Kind) -> Bool = { [weak self] in
      self?.canCapture?($0, $1) ?? false
    }
    buttonInterceptor = MouseButtonInterceptor(
      keys: keys, takesGaps: gaps, canCapture: canCapture
    ) { [weak self] event in
      self?.continuation.yield(event)
    }
  }

  private func removeButtonInterceptor() {
    buttonInterceptor?.invalidate()
    buttonInterceptor = nil
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
