import CoreGraphics

extension CGRect {
  /// Whether `other` is within a point of this rect in position and size. Apps round frames, so
  /// a window counts as in its slot when it is this close.
  package func isClose(to other: CGRect) -> Bool {
    abs(minX - other.minX) <= 1 && abs(minY - other.minY) <= 1
      && abs(width - other.width) <= 1 && abs(height - other.height) <= 1
  }

  /// Whether `other` differs from this rect in size by more than a point: a window dragged to
  /// another size was resized, one of the same size only moved.
  package func hasOtherSize(than other: CGRect) -> Bool {
    abs(width - other.width) > 1 || abs(height - other.height) > 1
  }

  /// Where a window now at `current` goes before it is resized to this rect: up or left, so it
  /// reaches no further than this rect's bottom and right edges. macOS clamps the bottom edge of a
  /// window that reaches past the bottom of its display onto another when it shrinks it to just
  /// above that edge (see `devdocs/macos-behaviour.md`); one that doesn't reach past it shrinks as
  /// asked. `nil` when the window reaches past neither edge, give or take a point.
  package func clearingOrigin(from current: CGRect) -> CGPoint? {
    let isPastRight = current.maxX > maxX + 1
    let isPastBottom = current.maxY > maxY + 1
    guard isPastRight || isPastBottom, intersects(current) else { return nil }
    return CGPoint(
      x: isPastRight ? maxX - current.width : current.minX,
      y: isPastBottom ? maxY - current.height : current.minY)
  }
}
