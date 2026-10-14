// The displays as tyler sees them: numbers, frames and parking edges. The numbering and the edge
// rule copy what TylerCore computes (this tool doesn't link it), so `displays` can show where
// tyler would park before tyler does it.

import AppKit

/// One display in Accessibility coordinates (origin top-left of the primary display, y down).
struct Display {
  let number: Int
  let id: CGDirectDisplayID
  let name: String
  let frame: CGRect
  /// The area not covered by the menu bar and Dock.
  let visible: CGRect

  /// The primary display (the one with the menu bar).
  init?() {
    guard let primary = Display.all().first else { return nil }
    self = primary
  }

  /// The display tyler numbers `number` (1 is the primary).
  init?(number: Int) {
    guard let display = Display.all().first(where: { $0.number == number }) else { return nil }
    self = display
  }

  private init(number: Int, screen: NSScreen, primaryHeight: CGFloat) {
    self.number = number
    let key = NSDeviceDescriptionKey("NSScreenNumber")
    id = (screen.deviceDescription[key] as? NSNumber)?.uint32Value ?? 0
    name = screen.localizedName
    frame = Display.axRect(screen.frame, primaryHeight: primaryHeight)
    visible = Display.axRect(screen.visibleFrame, primaryHeight: primaryHeight)
  }

  /// Every display, numbered: the primary first, then left to right, then top to bottom.
  static func all() -> [Display] {
    let screens = NSScreen.screens
    guard let primary = screens.first else { return [] }
    let height = primary.frame.height
    let others = screens.dropFirst().sorted {
      let left = axRect($0.frame, primaryHeight: height)
      let right = axRect($1.frame, primaryHeight: height)
      return (left.minX, left.minY) < (right.minX, right.minY)
    }
    return ([primary] + others).enumerated().map { index, screen in
      Display(number: index + 1, screen: screen, primaryHeight: height)
    }
  }

  private static func axRect(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
    CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
  }

  /// The display's UUID, which survives reboots (the id may not).
  var uuid: String {
    guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return "?" }
    return CFUUIDCreateString(nil, uuid) as String? ?? "?"
  }

  /// The edge tyler would park windows at: the right one unless another display lies to the
  /// right at the same height, then the left one; nil when both are taken.
  func parkingEdge(among displays: [Display]) -> String? {
    let others = displays.filter { $0.id != id && overlapsVertically($0) }
    if !others.contains(where: { $0.frame.minX >= frame.maxX - 1 }) { return "right" }
    if !others.contains(where: { $0.frame.maxX <= frame.minX + 1 }) { return "left" }
    return nil
  }

  private func overlapsVertically(_ other: Display) -> Bool {
    other.frame.minY < visible.maxY && other.frame.maxY > visible.minY
  }
}

/// `displays`: every display as tyler numbers it, with its parking edge.
@MainActor
func displays() {
  // NSScreen leaves the top strip of a display without the menu bar out of its visible frame only
  // once the process is an app, as tylerd is.
  _ = NSApplication.shared
  let all = Display.all()
  print("displays have separate Spaces: \(NSScreen.screensHaveSeparateSpaces ? "on" : "off")")
  for display in all {
    let edge = display.parkingEdge(among: all).map { "parks at the \($0) edge" } ?? "no free edge"
    print("display \(display.number)\(display.number == 1 ? " (primary)" : "")  \(display.name)")
    print("  id \(display.id), uuid \(display.uuid)")
    print("  frame \(format(display.frame)), visible frame \(format(display.visible))")
    print("  \(edge)")
  }
}

/// Whether a window is an overlay that tylerd looks past: at the cursor's layer or above (the
/// cursor while the screen is shared), or above the normal layer and covering exactly a whole
/// display, as the Dock's and Notification Centre's do. The same rule as `PointerFocus.isOverlay`
/// in the package, which this standalone tool can't import.
func isOverlay(layer: Int, frame: CGRect) -> Bool {
  if layer >= Int(CGWindowLevelForKey(.cursorWindow)) { return true }
  var count: UInt32 = 0
  guard layer > 0, CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
    return false
  }
  var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
  guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return false }
  return ids.prefix(Int(count)).contains { CGDisplayBounds($0) == frame }
}
