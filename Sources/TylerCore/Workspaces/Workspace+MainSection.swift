/// The master section of `tall`: the first windows of the list, stacked in the left column.
extension Workspace {
  package var mainSectionCount: Int {
    layoutStates.tall.mainCount(for: count)
  }

  /// Moves the focused window from the stack to the end of the master section. Returns false if
  /// it is in the master section already.
  @discardableResult
  package mutating func promote() -> Bool {
    guard let focused, let index = focusedIndex, index >= mainSectionCount else { return false }
    return move(focused, to: ListPlace(index: mainSectionCount, isInMainSection: true))
  }

  /// Moves the focused window from the master section to the top of the stack. The only master
  /// gives its place to the window after it. Returns false if it is in the stack already, or
  /// alone.
  @discardableResult
  package mutating func demote() -> Bool {
    guard let focused, let index = focusedIndex, index < mainSectionCount, count > 1 else {
      return false
    }
    return move(focused, to: ListPlace(index: max(mainSectionCount - 1, 1)))
  }
}
