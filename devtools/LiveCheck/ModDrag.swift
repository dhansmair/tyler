// `mod-drag`: the spike for moving and resizing with a modifier. An active
// event tap holds back each mouse-down made with the modifier. If the pointer then moves past a
// threshold, the drag is the probe's: it logs it as a move (left button) or a resize (right) and
// swallows the rest of it, so the app sees nothing. If the button comes up first, the probe posts
// the held mouse-down and the mouse-up again, so the app still gets its modifier+click. No window
// is moved: this only checks what macOS lets the tap do.

import AppKit
import CoreGraphics

/// Marks the events the probe posts itself, so its tap lets them through.
private let replayMarker: Int64 = 0x7479_6C72  // "tylr"

/// How far the pointer must move before a held mouse-down becomes a drag, in points.
private let dragThreshold: CGFloat = 4

@MainActor
private final class ModDragProbe {
  let modifier: CGEventFlags
  let stall: TimeInterval
  var tap: CFMachPort?

  /// The mouse-down held back, while it is undecided or its drag is ours.
  private var held: CGEvent?
  private var heldAt = Date()
  private var isDragging = false
  private var drags = 0

  init(modifier: CGEventFlags, stall: TimeInterval) {
    self.modifier = modifier
    self.stall = stall
  }

  /// Returns whether to swallow the event.
  func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
    if event.getIntegerValueField(.eventSourceUserData) == replayMarker { return false }
    let start = Date()
    defer {
      let elapsed = Date().timeIntervalSince(start) * 1000
      if elapsed > 5 { print(String(format: "  (callback took %.1f ms)", elapsed)) }
    }
    switch type {
    case .leftMouseDown, .rightMouseDown: return down(type, event)
    case .leftMouseDragged, .rightMouseDragged: return dragged(event)
    case .leftMouseUp, .rightMouseUp: return up(event)
    default: return false
    }
  }

  private func down(_ type: CGEventType, _ event: CGEvent) -> Bool {
    if held != nil {
      // The other button while one is held: ours too, so the app sees no stray down.
      print("other button pressed during a held press: swallowed")
      return true
    }
    let relevant: CGEventFlags = [.maskAlternate, .maskControl, .maskCommand, .maskShift]
    guard event.flags.intersection(relevant) == modifier else {
      // Logged too, so an empty log means the tap got no clicks at all.
      print("down without the modifier (flags \(String(event.flags.rawValue, radix: 16))): passed")
      return false
    }
    let button = type == .leftMouseDown ? "left" : "right"
    let clicks = event.getIntegerValueField(.mouseEventClickState)
    let windowStart = Date()
    let window = topmostWindow(at: event.location)
    let windowTime = Date().timeIntervalSince(windowStart) * 1000
    print(
      String(
        format: "%@ down at %@ (click %d) over %@, window list %.2f ms: held", button,
        format(event.location), clicks, window, windowTime))
    held = event.copy()
    heldAt = Date()
    isDragging = false
    drags = 0
    if stall > 0 {
      print(String(format: "  stalling the main thread for %.0f ms", stall * 1000))
      Thread.sleep(forTimeInterval: stall)
    }
    return true
  }

  private func dragged(_ event: CGEvent) -> Bool {
    guard let held else { return false }
    let delta = CGPoint(
      x: event.location.x - held.location.x, y: event.location.y - held.location.y)
    if !isDragging, hypot(delta.x, delta.y) >= dragThreshold {
      isDragging = true
      let kind = held.type == .leftMouseDown ? "move" : "resize"
      print(
        String(format: "  %@ began after %.0f ms", kind, Date().timeIntervalSince(heldAt) * 1000))
    }
    drags += 1
    return true
  }

  private func up(_ event: CGEvent) -> Bool {
    guard let held else { return false }
    self.held = nil
    if isDragging {
      let delta = CGPoint(
        x: event.location.x - held.location.x, y: event.location.y - held.location.y)
      print("  ended at \(format(event.location)), delta \(format(delta)), \(drags) drag events")
      return true
    }
    // A click: post the held down and this up again, marked so the tap lets them through.
    let elapsed = Date().timeIntervalSince(heldAt) * 1000
    guard let press = held.copy(), let release = event.copy() else {
      print("  click: copying failed, the app gets only the up")
      return false
    }
    press.setIntegerValueField(.eventSourceUserData, value: replayMarker)
    release.setIntegerValueField(.eventSourceUserData, value: replayMarker)
    press.post(tap: .cgSessionEventTap)
    release.post(tap: .cgSessionEventTap)
    print(String(format: "  click after %.0f ms (%d small drags): replayed", elapsed, drags))
    return true
  }

  func turnBackOn(_ type: CGEventType) {
    print(
      "tap turned off by macOS (\(type == .tapDisabledByTimeout ? "timeout" : "user input")): turning it back on"
    )
    if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    // Whatever was held is lost with the events macOS let through meanwhile.
    if held != nil { print("  dropping the held press") }
    held = nil
  }

  private func topmostWindow(at point: CGPoint) -> String {
    let list =
      CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    for entry in list {
      let bounds = entry[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
      let frame = CGRect(
        x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0, width: bounds["Width"] ?? 0,
        height: bounds["Height"] ?? 0)
      let layer = entry[kCGWindowLayer as String] as? Int ?? 0
      let owner = entry[kCGWindowOwnerName as String] as? String ?? "?"
      guard frame.contains(point), !isOverlay(layer: layer, frame: frame) else {
        continue
      }
      let number = entry[kCGWindowNumber as String] as? Int ?? 0
      return "\(number) \(owner) layer \(layer)"
    }
    return "nothing"
  }
}

private func modifierFlags(_ name: String) -> CGEventFlags? {
  var flags: CGEventFlags = []
  for part in name.split(separator: "+") {
    switch part {
    case "option": flags.insert(.maskAlternate)
    case "ctrl": flags.insert(.maskControl)
    case "cmd": flags.insert(.maskCommand)
    case "shift": flags.insert(.maskShift)
    default: return nil
    }
  }
  return flags.isEmpty ? nil : flags
}

/// `mod-drag <seconds> [modifier] [stall-ms]`: runs the tap for `seconds`. `modifier` is
/// `option` (default) or a combination such as `ctrl+option`. `stall-ms` blocks the main thread
/// at each held press, to see what macOS does with a slow tap.
@MainActor
func modDrag(_ arguments: [String]) throws(UsageError) {
  guard (1...3).contains(arguments.count), let seconds = Double(arguments[0]), seconds > 0,
    let modifier = modifierFlags(arguments.count >= 2 ? arguments[1] : "option"),
    let stallMilliseconds = Double(arguments.count == 3 ? arguments[2] : "0")
  else {
    throw UsageError("mod-drag <seconds> [option|ctrl|cmd|shift, joined by +] [stall-ms]")
  }
  _ = NSApplication.shared
  setlinebuf(stdout)
  let probe = ModDragProbe(modifier: modifier, stall: stallMilliseconds / 1000)
  let types: [CGEventType] = [
    .leftMouseDown, .leftMouseUp, .leftMouseDragged,
    .rightMouseDown, .rightMouseUp, .rightMouseDragged,
  ]
  let mask = types.reduce(CGEventMask(0)) { $0 | CGEventMask(1) << CGEventMask($1.rawValue) }
  let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
    eventsOfInterest: mask,
    callback: { _, type, event, refcon in
      guard let refcon else { return Unmanaged.passUnretained(event) }
      let address = UInt(bitPattern: refcon)
      // The source is on the main run loop, so this runs on the main thread.
      let swallow = MainActor.assumeIsolated {
        guard let pointer = UnsafeMutableRawPointer(bitPattern: address) else { return false }
        let probe = Unmanaged<ModDragProbe>.fromOpaque(pointer).takeUnretainedValue()
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
          probe.turnBackOn(type)
          return false
        }
        return probe.handle(type, event)
      }
      return swallow ? nil : Unmanaged.passUnretained(event)
    },
    userInfo: Unmanaged.passUnretained(probe).toOpaque())
  guard let tap else { throw UsageError("the active event tap was refused (missing permission?)") }
  probe.tap = tap
  CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
  CGEvent.tapEnable(tap: tap, enable: true)
  print("listening for \(Int(seconds)) s: drag and click with the modifier, left and right")
  RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds))
  CFMachPortInvalidate(tap)
}
