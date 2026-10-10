import CoreGraphics

extension CGRect {
  /// Whether `other` is within a point of this rect in position and size. Apps round frames, so
  /// a window counts as in its slot when it is this close.
  public func isClose(to other: CGRect) -> Bool {
    abs(minX - other.minX) <= 1 && abs(minY - other.minY) <= 1
      && abs(width - other.width) <= 1 && abs(height - other.height) <= 1
  }

  /// Whether `other` differs from this rect in size by more than a point: a window dragged to
  /// another size was resized, one of the same size only moved.
  public func hasOtherSize(than other: CGRect) -> Bool {
    abs(width - other.width) > 1 || abs(height - other.height) > 1
  }
}
