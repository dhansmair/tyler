import CoreGraphics

/// One window's path during an animation: a straight line from `start` to `end` (top-left
/// corners in Accessibility coordinates), with x kept inside `allowedX`. `start` and `end` may
/// lie outside it; `position(at:)` is where the window really goes.
public struct Track: Equatable, Sendable {
  public let id: WindowID
  public let start: CGPoint
  public let end: CGPoint
  /// The horizontal positions the window may take. Every window of a slide moves by the same
  /// distance, and one that reaches the edge of this range waits there instead of being asked
  /// for a position macOS would pull back on screen.
  public let allowedX: ClosedRange<CGFloat>

  public init(
    id: WindowID,
    start: CGPoint,
    end: CGPoint,
    allowedX: ClosedRange<CGFloat> = -CGFloat.infinity...CGFloat.infinity
  ) {
    self.id = id
    self.start = start
    self.end = end
    self.allowedX = allowedX
  }

  /// A window leaving the display from `frame`, in the direction the view scrolls.
  public static func leaving(
    _ id: WindowID, from frame: CGRect, direction: ScrollDirection, on display: DisplayInfo
  ) -> Track {
    let offset = direction.outgoingOffset(width: display.visibleFrame.width)
    return Track(
      id: id, start: frame.origin, end: frame.offsetBy(dx: offset, dy: 0).origin,
      allowedX: Parking.allowedX(width: frame.width, on: display))
  }

  /// A window entering the display into `slot`, from the side opposite to where the current
  /// windows leave.
  public static func entering(
    _ id: WindowID, into slot: CGRect, direction: ScrollDirection, on display: DisplayInfo
  ) -> Track {
    let offset = direction.outgoingOffset(width: display.visibleFrame.width)
    return Track(
      id: id, start: slot.offsetBy(dx: -offset, dy: 0).origin, end: slot.origin,
      allowedX: Parking.allowedX(width: slot.width, on: display))
  }

  /// The position at `progress` (0 is `start`, 1 is `end`; values outside are clamped), eased,
  /// rounded to whole points so apps aren't asked for fractional positions, and with x kept
  /// inside `allowedX`. The easing runs over the whole path, so the windows of a slide move
  /// together like one page and each stops when it reaches the edge.
  public func position(at progress: Double) -> CGPoint {
    let eased = Easing.easeInOut(progress)
    let along = (start.x + (end.x - start.x) * eased).rounded()
    return CGPoint(
      x: min(allowedX.upperBound, max(allowedX.lowerBound, along)),
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

/// Which way the view scrolls when changing workspaces. The workspaces are a stack, but the
/// slide is horizontal because macOS won't let windows leave through the top or bottom of the
/// display (see `Parking`). Moving `down` the stack slides the current windows out to the left
/// while the next workspace's windows come in from the right.
public enum ScrollDirection: Equatable, Sendable {
  case up
  case down

  /// How far outgoing windows travel horizontally for a visible frame of `width`; incoming
  /// windows start the same distance away on the opposite side.
  public func outgoingOffset(width: CGFloat) -> CGFloat {
    self == .down ? -width : width
  }
}
