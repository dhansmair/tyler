/// The master section of `tall`: the first windows of the list, stacked in the left column.
extension Workspace {
  package var mainSectionCount: Int {
    layoutStates.tall.mainCount(for: count)
  }

  package func isInMainSection(_ windowID: WindowID) -> Bool {
    windows.firstIndex(of: windowID).map { $0 < mainSectionCount } ?? false
  }

  /// Moves the focused window from the stack to the end of the master section. Returns false if
  /// it is in the master section already.
  @discardableResult
  package mutating func promote() -> Bool {
    guard let index = focusedIndex, index >= mainSectionCount else { return false }
    let count = count
    moveWindow(at: index, to: mainSectionCount)
    update(\.tall) { state, _ in state.growMainSection(of: count) }
    return true
  }

  /// Moves the focused window from the master section to the top of the stack. The only master
  /// gives its place to the window after it. Returns false if it is in the stack already, or
  /// alone.
  @discardableResult
  package mutating func demote() -> Bool {
    guard let index = focusedIndex, index < mainSectionCount, count > 1 else { return false }
    let count = count
    let isOnlyMain = mainSectionCount == 1
    moveWindow(at: index, to: isOnlyMain ? 1 : mainSectionCount - 1)
    if !isOnlyMain { update(\.tall) { state, _ in state.shrinkMainSection(of: count) } }
    return true
  }
}
