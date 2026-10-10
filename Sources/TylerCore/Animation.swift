import CoreGraphics

/// One window's path during an animation: a straight line from `start` to `end` (top-left
/// corners in Accessibility coordinates).
public struct Track: Equatable, Sendable {
  public let id: WindowID
  public let start: CGPoint
  public let end: CGPoint

  public init(id: WindowID, start: CGPoint, end: CGPoint) {
    self.id = id
    self.start = start
    self.end = end
  }

  /// The position at `progress` (0 is `start`, 1 is `end`; values outside are clamped), eased
  /// and rounded to whole points so apps aren't asked for fractional positions.
  public func position(at progress: Double) -> CGPoint {
    let eased = Easing.easeInOut(progress)
    return CGPoint(
      x: (start.x + (end.x - start.x) * eased).rounded(),
      y: (start.y + (end.y - start.y) * eased).rounded())
  }
}

public enum Easing {
  /// Cubic ease-in-out: slow at both ends, symmetric around the midpoint.
  public static func easeInOut(_ progress: Double) -> Double {
    let clamped = min(1, max(0, progress))
    if clamped < 0.5 { return 4 * clamped * clamped * clamped }
    let rest = -2 * clamped + 2
    return 1 - rest * rest * rest / 2
  }
}

/// Which way the view scrolls when changing workspaces. Moving `down` the stack slides the
/// current windows up and out while the next workspace's windows rise in from below.
public enum ScrollDirection: Equatable, Sendable {
  case up
  case down

  /// How far outgoing windows travel vertically for a display of `height`; incoming windows
  /// start the same distance away on the opposite side.
  public func outgoingOffset(height: CGFloat) -> CGFloat {
    self == .down ? -height : height
  }
}
