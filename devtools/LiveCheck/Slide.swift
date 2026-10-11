// `slide`: replays a workspace switch on real windows, the way tylerd does it, so a change to
// the motion can be judged by eye before it goes into tylerd.

import AppKit
import ApplicationServices

/// One window taking part in the replay.
private struct Mover {
  let element: AXUIElement
  /// Where the window was before the replay; it goes back there at the end.
  let start: CGPoint
  /// Where the window is when its page is on screen.
  let slot: CGPoint
  let width: CGFloat
}

/// Where windows of hidden workspaces rest: just past the right or the left edge of the display.
private enum ParkingEdge: String {
  case right, left

  func parked(_ mover: Mover, on display: Display) -> CGPoint {
    let visible = display.visible
    switch self {
    case .right: return CGPoint(x: visible.maxX - 1, y: mover.slot.y)
    case .left: return CGPoint(x: visible.minX - mover.width + 1, y: mover.slot.y)
    }
  }
}

/// The options of `slide`: the display to slide on and the edge its windows park at.
private struct SlideOptions {
  var display = 1
  var edge = ParkingEdge.right

  /// Takes `--display <n>` and `--park left|right` out of `arguments`.
  init(taking arguments: inout [String]) throws(UsageError) {
    if let flag = arguments.firstIndex(of: "--display") {
      guard flag + 1 < arguments.count, let number = Int(arguments[flag + 1]) else {
        throw UsageError("--display needs a display number (see `displays`)")
      }
      display = number
      arguments.removeSubrange(flag...(flag + 1))
    }
    if let flag = arguments.firstIndex(of: "--park") {
      guard flag + 1 < arguments.count, let parsed = ParkingEdge(rawValue: arguments[flag + 1])
      else { throw UsageError("--park needs left or right") }
      edge = parsed
      arguments.removeSubrange(flag...(flag + 1))
    }
  }
}

/// `slide <seconds> <rounds> <out-ids> <in-id@x,y>... [--display <n>] [--park left|right]`: the
/// `out` windows (comma-separated ids, at their current positions) slide out to the left while the
/// `in` windows come in from the right edge into the given slots; then it all reverses. Between
/// slides, windows that are off the page rest at the parking edge, as tylerd will park them: with
/// `--park left`, the incoming ones jump from the left edge to the right one before sliding in.
/// Every window ends where it started.
func slide(_ given: [String]) throws(UsageError) {
  let syntax =
    "slide <seconds> <rounds> <out-ids> <in-id@x,y>... [--display <n>] [--park left|right]"
  var arguments = given
  let options = try SlideOptions(taking: &arguments)
  guard arguments.count >= 3, let seconds = Double(arguments[0]), let rounds = Int(arguments[1])
  else { throw UsageError(syntax) }
  guard let display = Display(number: options.display) else {
    throw UsageError("no display \(options.display) (see `displays`)")
  }
  let windows = Accessibility.windows()
  let outgoing = try arguments[2].split(separator: ",").map { field throws(UsageError) in
    try mover(String(field), slot: nil, in: windows)
  }
  let incoming = try arguments.dropFirst(3).map { field throws(UsageError) in
    let parts = field.split(separator: "@")
    let slot = parts.count == 2 ? point(String(parts[1])) : nil
    guard let slot else { throw UsageError("\(field): expected <id>@<x>,<y>") }
    return try mover(String(parts[0]), slot: slot, in: windows)
  }

  print("display \(display.number), parking at the \(options.edge.rawValue) edge")
  park(incoming, at: options.edge, on: display)
  for count in [3, 2, 1] {
    print("starting in \(count)…")
    sleep(1)
  }
  let width = display.visible.width
  for round in 1...max(1, rounds) {
    print("round \(round): out to the left, in from the right")
    run(
      outgoing.map { ($0, $0.slot.x) } + incoming.map { ($0, $0.slot.x + width) },
      by: -width, over: seconds, on: display)
    park(outgoing, at: options.edge, on: display)
    usleep(1_500_000)
    print("round \(round): back")
    run(
      incoming.map { ($0, $0.slot.x) } + outgoing.map { ($0, $0.slot.x - width) },
      by: width, over: seconds, on: display)
    park(incoming, at: options.edge, on: display)
    if round < rounds { sleep(1) }
  }
  report(outgoing + incoming)
  for mover in outgoing + incoming {
    Accessibility.setOrigin(mover.start, of: mover.element)
  }
  print("windows put back")
}

/// Puts the windows at their parking spot, as tylerd does once a slide ends.
private func park(_ movers: [Mover], at edge: ParkingEdge, on display: Display) {
  for mover in movers {
    Accessibility.setOrigin(edge.parked(mover, on: display), of: mover.element)
  }
}

/// Prints any window whose size macOS changed during the replay, such as one that crossed onto a
/// display with another height or scale.
private func report(_ movers: [Mover]) {
  for mover in movers {
    guard let size = Accessibility.size(of: mover.element) else { continue }
    let note =
      abs(size.width - mover.width) < 1 ? "same width" : "WIDTH CHANGED from \(Int(mover.width))"
    print("  window at \(format(mover.start)): now \(Int(size.width))x\(Int(size.height)), \(note)")
  }
}

private func mover(
  _ field: String, slot: CGPoint?, in windows: [CGWindowID: AXUIElement]
) throws(UsageError) -> Mover {
  guard let windowID = CGWindowID(field), let element = windows[windowID],
    let origin = Accessibility.origin(of: element), let size = Accessibility.size(of: element)
  else { throw UsageError("no window \(field) (see `tyler list`)") }
  return Mover(element: element, start: origin, slot: slot ?? origin, width: size.width)
}

private func point(_ text: String) -> CGPoint? {
  let parts = text.split(separator: ",").map(String.init)
  guard parts.count == 2 else { return nil }
  return point(x: parts[0], y: parts[1])
}

/// Moves each window from its start x by `delta` over `seconds`, eased, keeping x inside the
/// range macOS accepts (as tyler's `Parking.allowedX` does). Progress follows the clock.
private func run(
  _ movers: [(Mover, CGFloat)], by delta: CGFloat, over seconds: Double, on display: Display
) {
  let start = Date()
  var frames = 0
  while true {
    let progress = min(1, Date().timeIntervalSince(start) / seconds)
    let eased = progress < 0.5 ? 4 * pow(progress, 3) : 1 - pow(-2 * progress + 2, 3) / 2
    for (mover, fromX) in movers {
      let lowest = display.visible.minX - mover.width + 1
      let wanted = (fromX + delta * eased).rounded()
      let clampedX = min(display.visible.maxX - 1, max(lowest, wanted))
      Accessibility.setOrigin(CGPoint(x: clampedX, y: mover.slot.y), of: mover.element)
    }
    frames += 1
    if progress >= 1 { break }
    usleep(8_000)
  }
  let elapsed = Int(Date().timeIntervalSince(start) * 1000)
  print("  \(frames) frames in \(elapsed) ms")
}
