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

/// `slide <seconds> <rounds> <out-ids> <in-id@x,y>...`: the `out` windows (comma-separated ids,
/// at their current positions) slide out to the left while the `in` windows come in from the
/// right edge into the given slots; then it all reverses. Every window ends where it started.
func slide(_ arguments: [String]) throws(UsageError) {
  let syntax = "slide <seconds> <rounds> <out-ids> <in-id@x,y>..."
  guard arguments.count >= 3, let seconds = Double(arguments[0]), let rounds = Int(arguments[1])
  else { throw UsageError(syntax) }
  guard let display = Display() else { throw UsageError("no display") }
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
    usleep(1_500_000)
    print("round \(round): back")
    run(
      incoming.map { ($0, $0.slot.x) } + outgoing.map { ($0, $0.slot.x - width) },
      by: width, over: seconds, on: display)
    if round < rounds { sleep(1) }
  }
  for mover in outgoing + incoming {
    Accessibility.setOrigin(mover.start, of: mover.element)
  }
  print("windows put back")
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
