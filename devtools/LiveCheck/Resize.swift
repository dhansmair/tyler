// `resize`: asks macOS for a window frame write by write, in the order tylerd uses and the other
// way round, and reports what each write really did. Shows sizes macOS refuses (a window reaching
// past the bottom of its display onto another won't shrink) and sizes apps round (terminals).

import AppKit
import ApplicationServices

/// The orders the frame can be written in. tylerd's full write is `sizeFirst`.
private enum WriteOrder: String, CaseIterable {
  case sizeFirst = "size-first"
  case moveFirst = "move-first"

  var steps: [Step] {
    switch self {
    case .sizeFirst: [.size, .position, .size]
    case .moveFirst: [.position, .size]
    }
  }

  enum Step: String {
    case size, position
  }
}

/// `resize <window-id> <x> <y> <width> <height> [--order size-first|move-first]`: writes the frame
/// in each order (or the one given), each from where the window was, and prints the frame after
/// every write. Puts the window back afterwards.
func resize(_ given: [String]) throws(UsageError) {
  var arguments = given
  var orders = WriteOrder.allCases
  if let flag = arguments.firstIndex(of: "--order") {
    guard flag + 1 < arguments.count, let order = WriteOrder(rawValue: arguments[flag + 1]) else {
      throw UsageError("--order needs size-first or move-first")
    }
    orders = [order]
    arguments.removeSubrange(flag...(flag + 1))
  }
  let usage = "resize <window-id> <x> <y> <width> <height> [--order size-first|move-first]"
  guard arguments.count == 5, let windowID = CGWindowID(arguments[0]),
    let origin = point(x: arguments[1], y: arguments[2]),
    let size = point(x: arguments[3], y: arguments[4]).map({ CGSize(width: $0.x, height: $0.y) })
  else { throw UsageError(usage) }
  guard let window = Accessibility.windows()[windowID], let home = frame(of: window) else {
    throw UsageError("no window \(windowID) (see `tyler window list`)")
  }
  let target = CGRect(origin: origin, size: size)
  print("window \(windowID) at \(format(home)), asking for \(format(target))")
  for order in orders {
    print("\(order.rawValue):")
    write(target, in: order, to: window)
    let ended = put(window, back: home)
    print("  put back at \(format(ended))\(ended == home ? "" : "  NOT WHERE IT WAS")")
  }
}

private func write(_ target: CGRect, in order: WriteOrder, to window: AXUIElement) {
  for step in order.steps {
    let before = frame(of: window)
    let status =
      step == .size
      ? Accessibility.setSize(target.size, of: window)
      : Accessibility.setOrigin(target.origin, of: window)
    usleep(120_000)  // let the app and the WindowServer catch up
    let after = frame(of: window)
    let label = step.rawValue.padding(toLength: 9, withPad: " ", startingAt: 0)
    let result = after.map(format) ?? "?"
    print("  \(label) -> \(result)  \(verdict(step, asked: target, before: before, after: after))")
    if status != .success { print("  (AX error \(status.rawValue))") }
  }
}

/// What a write did: what was asked, nothing at all, or something else.
private func verdict(
  _ step: WriteOrder.Step, asked target: CGRect, before: CGRect?, after: CGRect?
) -> String {
  guard let after else { return "UNREADABLE" }
  let isClose: Bool
  switch step {
  case .size:
    isClose =
      abs(after.width - target.width) <= 1 && abs(after.height - target.height) <= 1
  case .position:
    isClose = abs(after.minX - target.minX) <= 1 && abs(after.minY - target.minY) <= 1
  }
  if isClose { return "ok" }
  if step == .size, after.size == before?.size { return "REFUSED (size unchanged)" }
  return step == .size ? "OTHER SIZE (the app chose it)" : "CLAMPED"
}

/// Puts the window back at `home` the way tylerd would, retrying from a spot that doesn't reach
/// past `home`'s bottom right if it stayed too big. Returns where it ended.
private func put(_ window: AXUIElement, back home: CGRect) -> CGRect {
  for _ in 0..<2 {
    Accessibility.setSize(home.size, of: window)
    Accessibility.setOrigin(home.origin, of: window)
    Accessibility.setSize(home.size, of: window)
    usleep(120_000)
    guard let now = frame(of: window), now.size != home.size else { break }
    Accessibility.setOrigin(
      CGPoint(x: home.maxX - now.width, y: home.maxY - now.height), of: window)
  }
  return frame(of: window) ?? .zero
}

private func frame(of window: AXUIElement) -> CGRect? {
  guard let origin = Accessibility.origin(of: window), let size = Accessibility.size(of: window)
  else { return nil }
  return CGRect(origin: origin, size: size)
}
