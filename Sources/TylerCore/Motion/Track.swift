import CoreGraphics

/// One window's path during an animation: a straight line from `start` to `end` (top-left
/// corners in Accessibility coordinates), with x kept inside `allowedX`. `start` and `end` may
/// lie outside it; `position(at:)` is where the window really goes.
package struct Track: Equatable, Sendable {
  package let id: WindowID
  package let start: CGPoint
  package let end: CGPoint
  /// The horizontal positions the window may take. Every window of a slide moves by the same
  /// distance, and one that reaches the edge of this range waits there instead of being asked
  /// for a position macOS would pull back on screen.
  package let allowedX: ClosedRange<CGFloat>
  /// The sizes the window goes between, for a window that changes size along the way; `nil` for
  /// one that keeps its size.
  package let sizes: Sizes?

  package init(
    id: WindowID,
    start: CGPoint,
    end: CGPoint,
    allowedX: ClosedRange<CGFloat> = -CGFloat.infinity...CGFloat.infinity,
    sizes: Sizes? = nil
  ) {
    self.id = id
    self.start = start
    self.end = end
    self.allowedX = allowedX
    self.sizes = sizes
  }

  /// A window leaving the display from `frame`, in the direction the view scrolls.
  package static func leaving(
    _ id: WindowID, from frame: CGRect, direction: ScrollDirection, on display: DisplayInfo
  ) -> Track {
    let offset = direction.outgoingOffset(width: display.visibleFrame.width)
    return Track(
      id: id, start: frame.origin, end: frame.offsetBy(dx: offset, dy: 0).origin,
      allowedX: Parking.allowedX(width: frame.width, on: display))
  }

  /// A window entering the display into `slot`, from the side opposite to where the current
  /// windows leave.
  package static func entering(
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
  package func position(at progress: Double) -> CGPoint {
    position(at: progress, easing: Easing.easeInOut)
  }

  /// The position at `progress` with another easing; `Easing.linear` keeps the window exactly
  /// in step with whatever drives the progress, such as fingers on the trackpad.
  package func position(at progress: Double, easing: (Double) -> Double) -> CGPoint {
    let eased = easing(progress)
    let along = (start.x + (end.x - start.x) * eased).rounded()
    return CGPoint(
      x: CGFloat(along).clamped(to: allowedX),
      y: (start.y + (end.y - start.y) * eased).rounded())
  }

  /// The size at `progress`, eased like the position and rounded to whole points; `nil` for a
  /// window that keeps its size.
  package func size(at progress: Double, easing: (Double) -> Double) -> CGSize? {
    guard let sizes else { return nil }
    let eased = easing(progress)
    return CGSize(
      width: (sizes.start.width + (sizes.end.width - sizes.start.width) * eased).rounded(),
      height: (sizes.start.height + (sizes.end.height - sizes.start.height) * eased).rounded())
  }
}
