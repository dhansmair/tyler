import AppKit
import TylerCore
import TylerRuntime
import TylerServer

/// Takes over mouse presses made with the modifier or in a gap between tiled windows, through an
/// active event tap: it can swallow events, so the app under the pointer sees none of a drag tyler
/// takes. `ModifierGesture` decides what to swallow. A press held back that turns out to be a
/// click is posted again, marked so the tap lets it through (measured; see "Events and taps" in
/// `devdocs/macos-behaviour.md`).
///
/// The tap runs on the main thread, as the listeners' taps do. If the main thread is busy for
/// about a second (an app slow to answer an Accessibility call), macOS turns the tap off and lets
/// that gesture through to the app; the interceptor turns it back on and drops the press.
@MainActor
final class MouseButtonInterceptor {
  private static let log = TylerLog(category: "pointer")
  /// Marks the events the tap posts itself: "tylr".
  private static let replayMarker: Int64 = 0x7479_6C72

  let keys: ModifierKeys
  let takesGaps: Bool
  private var gesture: ModifierGesture
  private let canCapture: @MainActor (CGPoint, ModifierGesture.Kind) -> Bool
  private let report: (PointerEvent) -> Void
  /// The press held back, while the gesture is undecided or tyler's.
  private var held: CGEvent?
  private var tap: CFMachPort?
  private var source: CFRunLoopSource?

  /// Starts taking over presses made with exactly `keys`, and left presses with no keys in a gap
  /// if `takesGaps`. `canCapture` is asked at each such press; `report` gets the drags. Without
  /// permission to tap events, it logs that and lets every press through.
  init(
    keys: ModifierKeys, takesGaps: Bool,
    canCapture: @escaping @MainActor (CGPoint, ModifierGesture.Kind) -> Bool,
    report: @escaping (PointerEvent) -> Void
  ) {
    self.keys = keys
    self.takesGaps = takesGaps
    gesture = ModifierGesture(modifier: keys, takesGaps: takesGaps)
    self.canCapture = canCapture
    self.report = report
    let types: [CGEventType] = [
      .leftMouseDown, .leftMouseDragged, .leftMouseUp,
      .rightMouseDown, .rightMouseDragged, .rightMouseUp,
    ]
    let mask = types.reduce(CGEventMask(0)) { $0 | CGEventMask(1) << CGEventMask($1.rawValue) }
    guard
      let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
        eventsOfInterest: mask, callback: mouseButtonCallback,
        userInfo: Unmanaged.passUnretained(self).toOpaque())
    else {
      Self.log.error(
        "mouse button interceptor refused - moving windows with the modifier and resizing by the"
          + " gaps are off")
      return
    }
    let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
    // On the main run loop, so the callback runs on the main thread.
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    self.tap = tap
    self.source = source
    // The first read of the window list in a process takes 20–40 ms (measured in the spike).
    // Paying it now keeps it out of the tap at the first press.
    _ = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
  }

  /// Stops taking over presses. The tap holds an unretained pointer to this object, so this must
  /// run before it goes away.
  func invalidate() {
    if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
    if let tap { CFMachPortInvalidate(tap) }
    source = nil
    tap = nil
    held = nil
  }

  /// Returns whether to swallow the event.
  fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
    if event.getIntegerValueField(.eventSourceUserData) == Self.replayMarker { return false }
    // Event locations are global display coordinates with a top-left origin: the same as
    // Accessibility's.
    let location = event.location
    switch type {
    case .leftMouseDown, .rightMouseDown:
      let wasActive = gesture.isActive
      let verdict = gesture.pressed(
        type == .leftMouseDown ? .left : .right, at: location, keys: Self.keys(of: event.flags)
      ) { canCapture(location, $0) }
      if !wasActive && gesture.isActive { held = event.copy() }
      return verdict == .swallow
    case .leftMouseDragged, .rightMouseDragged:
      let (verdict, actions) = gesture.dragged(
        type == .leftMouseDragged ? .left : .right, to: location)
      perform(actions, release: event)
      return verdict == .swallow
    case .leftMouseUp, .rightMouseUp:
      let (verdict, actions) = gesture.released(type == .leftMouseUp ? .left : .right, at: location)
      perform(actions, release: event)
      if !gesture.isActive { held = nil }
      return verdict == .swallow
    default:
      return false
    }
  }

  /// macOS turns a tap off when its callback is slow: turn it back on. The gesture under way went
  /// to the app meanwhile, so the held press is dropped.
  fileprivate func turnBackOn() {
    if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    if gesture.isActive {
      Self.log.warning("mouse button interceptor turned off - mid-gesture; the press is dropped")
    }
    perform(gesture.tapTurnedOff(), release: nil)
    held = nil
  }

  private func perform(_ actions: [ModifierGesture.Action], release: CGEvent?) {
    for action in actions {
      switch action {
      case .began(let kind, let start): report(.modifierDragBegan(kind, location: start))
      case .moved(let location): report(.modifierDragMoved(location: location))
      case .ended(let location): report(.modifierDragEnded(location: location))
      case .replayClick: replay(release)
      }
    }
  }

  /// Posts the held press and `release` again, so the app gets the click.
  private func replay(_ release: CGEvent?) {
    guard let press = held?.copy(), let release = release?.copy() else {
      Self.log.error("modifier click passing failed - copying the events failed")
      return
    }
    press.setIntegerValueField(.eventSourceUserData, value: Self.replayMarker)
    release.setIntegerValueField(.eventSourceUserData, value: Self.replayMarker)
    press.post(tap: .cgSessionEventTap)
    release.post(tap: .cgSessionEventTap)
  }

  private static func keys(of flags: CGEventFlags) -> ModifierKeys {
    var keys: ModifierKeys = []
    if flags.contains(.maskAlternate) { keys.insert(.option) }
    if flags.contains(.maskControl) { keys.insert(.control) }
    if flags.contains(.maskCommand) { keys.insert(.command) }
    if flags.contains(.maskShift) { keys.insert(.shift) }
    return keys
  }
}

private let mouseButtonCallback: CGEventTapCallBack = { _, type, event, userInfo in
  guard let userInfo else { return Unmanaged.passUnretained(event) }
  let address = UInt(bitPattern: userInfo)
  let isTurnedOff = type == .tapDisabledByTimeout || type == .tapDisabledByUserInput
  // `CGEvent` isn't Sendable, but it never leaves this thread: `assumeIsolated` runs the closure
  // synchronously, here, and the tap returns the event only after it.
  nonisolated(unsafe) let event = event
  // The tap's run loop source is on the main run loop, so this runs on the main thread.
  let swallows = MainActor.assumeIsolated {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: address) else { return false }
    let tap = Unmanaged<MouseButtonInterceptor>.fromOpaque(pointer).takeUnretainedValue()
    if isTurnedOff {
      tap.turnBackOn()
      return false
    }
    return tap.handle(type, event)
  }
  return swallows ? nil : Unmanaged.passUnretained(event)
}
