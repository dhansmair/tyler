/// Where a window dragged onto another display would go in on release.
package struct Arrival: Equatable, Sendable {
  /// The display's position in the rows.
  package let position: Int
  /// The place in the list of that display's current workspace.
  package let index: Int

  package init(position: Int, index: Int) {
    self.position = position
    self.index = index
  }
}
