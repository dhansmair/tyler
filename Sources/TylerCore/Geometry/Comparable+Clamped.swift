extension Comparable {
  /// This value, moved into `range` if it lies outside.
  package func clamped(to range: ClosedRange<Self>) -> Self {
    min(max(self, range.lowerBound), range.upperBound)
  }
}
