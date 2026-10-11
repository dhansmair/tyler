import CoreGraphics

/// Where windows of inactive workspaces wait: just past the display's parking edge (the right
/// edge of its visible frame, or the left one when another display lies to the right), at their
/// own height, with one point still overlapping it.
///
/// macOS (measured on 26.7) only accepts a window position that overlaps the visible frame (the
/// display minus the menu bar and Dock) by at least a point horizontally; anything further is
/// pulled 40 points back in. Vertically it is stricter: a window can't go above the menu bar, and
/// 32 points of it must stay visible at the bottom. So the side edges are the only places a window
/// can almost disappear, and workspaces slide horizontally.
public enum Parking {
  /// How much of a parked window stays inside the visible frame, in points.
  static let visibleSliver: CGFloat = 1

  /// The parked frame for a window that is at `frame` on `display`. The size and height are
  /// kept, so the window doesn't have to be resized when it comes back and can slide straight
  /// in from where it waits.
  public static func frame(for frame: CGRect, on display: DisplayInfo) -> CGRect {
    let left =
      switch display.parkingEdge {
      case .right: display.visibleFrame.maxX - visibleSliver
      case .left: display.visibleFrame.minX - frame.width + visibleSliver
      }
    return CGRect(origin: CGPoint(x: left, y: frame.minY), size: frame.size)
  }

  /// The horizontal positions macOS accepts for a window of `width` on `display`: from hanging
  /// off the left edge of the visible frame to hanging off its right edge, a point showing
  /// either way.
  public static func allowedX(width: CGFloat, on display: DisplayInfo) -> ClosedRange<CGFloat> {
    let visible = display.visibleFrame
    return (visible.minX - width + visibleSliver)...(visible.maxX - visibleSliver)
  }
}
