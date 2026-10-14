import AppKit
import TylerCore
import TylerRuntime

/// Watches the trackpad for sideways swipes through a listen-only event tap on gesture events,
/// and reports them as swipes. A global `NSEvent` monitor gets no gesture events at all, while the
/// tap gets every touch frame, even with the same swipe assigned to Spaces in System Settings
/// (measured on macOS 26.7; see `devdocs/macos-behaviour.md`). Listen-only: the events still reach macOS
/// and the apps.
@MainActor
final class TrackpadGestureListener {
  private static let log = TylerLog(category: "pointer")

  var fingers: Int { recognizer.fingers }
  private var recognizer: SwipeRecognizer
  private let report: (SwipeUpdate) -> Void
  private var tap: CFMachPort?
  private var source: CFRunLoopSource?

  /// Starts watching for swipes with `fingers` fingers. Without permission to tap events, it logs
  /// that and stays silent.
  init(fingers: Int, report: @escaping (SwipeUpdate) -> Void) {
    recognizer = SwipeRecognizer(fingers: fingers)
    self.report = report
    // NSEvent.EventType.gesture is 29; CGEventType has no case for it.
    let mask = CGEventMask(1) << CGEventMask(NSEvent.EventType.gesture.rawValue)
    guard
      let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
        eventsOfInterest: mask, callback: trackpadGestureCallback,
        userInfo: Unmanaged.passUnretained(self).toOpaque())
    else {
      Self.log.error("trackpad gesture listener refused - swiping between workspaces is off")
      return
    }
    let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
    // On the main run loop, so the callback runs on the main thread.
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    self.tap = tap
    self.source = source
  }

  /// Stops watching. The tap holds an unretained pointer to this object, so this must run before
  /// it goes away.
  func invalidate() {
    if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
    if let tap { CFMachPortInvalidate(tap) }
    source = nil
    tap = nil
  }

  /// Feeds one gesture event's touches to the recognizer.
  fileprivate func handle(_ frame: TouchFrame) {
    for update in recognizer.feed(frame) {
      report(update)
    }
  }

  /// macOS turns a tap off when its callback is slow; turn it back on.
  fileprivate func turnBackOn() {
    if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
  }
}

private let trackpadGestureCallback: CGEventTapCallBack = { _, type, event, userInfo in
  guard let userInfo else { return Unmanaged.passUnretained(event) }
  // Only Sendable values cross into the main actor: the touches, and the object's address.
  let address = UInt(bitPattern: userInfo)
  let isTurnedOff = type == .tapDisabledByTimeout || type == .tapDisabledByUserInput
  var frame: TouchFrame?
  if let gesture = NSEvent(cgEvent: event), gesture.type == .gesture {
    let positions = gesture.touches(matching: .touching, in: nil).map(\.normalizedPosition)
    frame = TouchFrame(time: gesture.timestamp, positions: positions)
  }
  let touches = frame
  // The tap's run loop source is on the main run loop, so this runs on the main thread.
  MainActor.assumeIsolated {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: address) else { return }
    let tap = Unmanaged<TrackpadGestureListener>.fromOpaque(pointer).takeUnretainedValue()
    if isTurnedOff { tap.turnBackOn() }
    if let touches { tap.handle(touches) }
  }
  return Unmanaged.passUnretained(event)
}
