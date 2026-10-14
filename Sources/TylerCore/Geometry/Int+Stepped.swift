extension Int {
  /// The index `offset` steps from this one in a ring of `count`, wrapping around both ends.
  package func stepped(by offset: Int, wrappingAt count: Int) -> Int {
    ((self + offset) % count + count) % count
  }
}
