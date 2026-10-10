import AppKit
import OSLog
import TylerCore

/// Watches the trackpad for sideways swipes through a listen-only event tap on gesture events,
/// and reports them as pans. A global `NSEvent` monitor gets no gesture events at all, while the
/// tap gets every touch frame, even with the same swipe assigned to Spaces in System Settings
/// (measured on macOS 26.7; see M7 in the roadmap). Listen-only: the events still reach macOS
/// and the apps.
@MainActor
final class SwipeTap {
  private static let log = Logger(subsystem: "tyler", category: "pointer")

  var fingers: Int { recognizer.fingers }
  private var recognizer: PanRecognizer
  private let report: (PanUpdate) -> Void
  private var tap: CFMachPort?
  private var source: CFRunLoopSource?

  /// Starts watching for swipes with `fingers` fingers. Without permission to tap events, it logs
  /// that and stays silent.
  init(fingers: Int, report: @escaping (PanUpdate) -> Void) {
    recognizer = PanRecognizer(fingers: fingers)
    self.report = report
    // NSEvent.EventType.gesture is 29; CGEventType has no case for it.
    let mask = CGEventMask(1) << CGEventMask(NSEvent.EventType.gesture.rawValue)
    guard
      let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
        eventsOfInterest: mask, callback: swipeTapCallback,
        userInfo: Unmanaged.passUnretained(self).toOpaque())
    else {
      Self.log.error("cannot watch the trackpad: the event tap was refused")
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

private let swipeTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
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
    let tap = Unmanaged<SwipeTap>.fromOpaque(pointer).takeUnretainedValue()
    if isTurnedOff { tap.turnBackOn() }
    if let touches { tap.handle(touches) }
  }
  return Unmanaged.passUnretained(event)
}
