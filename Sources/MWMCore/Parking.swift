import CoreGraphics

/// Where windows of inactive monitors wait: in the display's bottom-right corner, with one
/// point still on screen. macOS tends to pull windows that are fully off screen back into view;
/// leaving a sliver visible avoids that (the technique AeroSpace uses).
public enum Parking {
  /// How much of a parked window stays on screen, in points, horizontally and vertically.
  public static let visibleSliver: CGFloat = 1

  /// The parked frame for a window of `size` on `display`. The size is kept so the window
  /// doesn't have to be resized when it comes back.
  public static func frame(for size: CGSize, on display: DisplayInfo) -> CGRect {
    CGRect(
      origin: CGPoint(
        x: display.frame.maxX - visibleSliver,
        y: display.frame.maxY - visibleSliver),
      size: size)
  }
}
