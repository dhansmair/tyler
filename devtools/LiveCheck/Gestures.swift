// `gestures`: logs the trackpad touches macOS hands out, from a listen-only event tap and from a
// global NSEvent monitor side by side, to find out which source tylerd can use for swipes.

import AppKit
import CoreGraphics

/// What one source saw: events per finger count, and when the first and last arrived.
private final class GestureLog {
  let name: String
  var countsByFingers: [Int: Int] = [:]
  var first: TimeInterval?
  var last: TimeInterval?
  var lastFingers = -1
  /// The contact in progress: its events and the touches' mean position at its start and now.
  var contactEvents = 0
  var contactStart: CGPoint?
  var contactNow: CGPoint?

  init(name: String) { self.name = name }

  func record(_ event: NSEvent) {
    let touches = event.allTouches().filter { $0.phase != .ended && $0.phase != .cancelled }
    let fingers = touches.count
    countsByFingers[fingers, default: 0] += 1
    first = first ?? event.timestamp
    last = event.timestamp
    let mean =
      touches.isEmpty
      ? nil
      : CGPoint(
        x: touches.map(\.normalizedPosition.x).reduce(0, +) / CGFloat(touches.count),
        y: touches.map(\.normalizedPosition.y).reduce(0, +) / CGFloat(touches.count))
    if fingers == lastFingers {
      contactEvents += 1
      contactNow = mean
      return
    }
    endContact()
    lastFingers = fingers
    contactEvents = 1
    contactStart = mean
    contactNow = mean
  }

  /// Prints the contact that just ended, if it had three or more fingers.
  func endContact() {
    guard lastFingers >= 3, let contactStart, let contactNow else { return }
    let travel = String(
      format: "dx %+.2f dy %+.2f", contactNow.x - contactStart.x, contactNow.y - contactStart.y)
    print("[\(name)] \(lastFingers) fingers: \(contactEvents) events, \(travel)")
  }

  func summary() -> String {
    endContact()
    let total = countsByFingers.values.reduce(0, +)
    guard total > 0, let first, let last else { return "\(name): no gesture events" }
    let rate = last > first ? Double(total) / (last - first) : 0
    let byFingers = countsByFingers.keys.sorted().map {
      "\($0) fingers: \(countsByFingers[$0] ?? 0)"
    }
    return "\(name): \(total) events, about \(Int(rate))/s while touching; "
      + byFingers.joined(separator: ", ")
  }
}

/// `gestures <seconds>`: listens for `seconds`, printing each change in finger count from both
/// sources, then a summary per source.
@MainActor
func gestures(_ arguments: [String]) throws(UsageError) {
  guard arguments.count == 1, let seconds = Double(arguments[0]), seconds > 0 else {
    throw UsageError("gestures <seconds>")
  }
  _ = NSApplication.shared
  let tapLog = GestureLog(name: "tap")
  let monitorLog = GestureLog(name: "monitor")

  // NSEvent.EventType.gesture is 29; CGEventType has no case for it.
  let mask = CGEventMask(1) << CGEventMask(NSEvent.EventType.gesture.rawValue)
  let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
    eventsOfInterest: mask,
    callback: { _, _, event, refcon in
      if let refcon, let nsEvent = NSEvent(cgEvent: event), nsEvent.type == .gesture {
        Unmanaged<GestureLog>.fromOpaque(refcon).takeUnretainedValue().record(nsEvent)
      }
      return Unmanaged.passUnretained(event)
    },
    userInfo: Unmanaged.passUnretained(tapLog).toOpaque())
  if let tap {
    let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
  } else {
    print("tap: could not be created (missing permission?)")
  }
  let monitor = NSEvent.addGlobalMonitorForEvents(matching: .gesture) { event in
    monitorLog.record(event)
  }
  if monitor == nil { print("monitor: could not be installed") }

  print("listening for \(Int(seconds)) s: swipe with 3 and 4 fingers, horizontally and vertically")
  RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds))
  if let monitor { NSEvent.removeMonitor(monitor) }
  print(tapLog.summary())
  print(monitorLog.summary())
}
