/// Moving the focus and windows along the list.
extension Workspace {
  /// Moves focus within the list, wrapping around. With nothing focused, `next` and `master`
  /// pick the first window and `prev` the last. Returns the newly focused window.
  @discardableResult
  package mutating func focus(_ target: ListTarget) -> WindowID? {
    guard !windows.isEmpty else { return nil }
    let index: Int
    switch target {
    case .main:
      index = 0
    case .next:
      index = focusedIndex.map { $0.stepped(by: 1, wrappingAt: windows.count) } ?? 0
    case .prev:
      index =
        focusedIndex.map { $0.stepped(by: -1, wrappingAt: windows.count) } ?? windows.count - 1
    }
    focused = windows[index]
    refitView()
    return focused
  }

  /// Swaps the focused window with its neighbour (wrapping) or with the master. If the focused
  /// window already is the master, `master` swaps it with the second window. The focused window
  /// keeps focus and moves with it. Returns false if there is nothing to swap.
  @discardableResult
  package mutating func swap(_ target: ListTarget) -> Bool {
    guard windows.count >= 2, let current = focusedIndex else { return false }
    let other: Int
    switch target {
    case .next: other = (current + 1) % windows.count
    case .prev: other = (current - 1 + windows.count) % windows.count
    case .main: other = current == 0 ? 1 : 0
    }
    swapSlots(current, other)
    return true
  }

  /// Swaps two windows' slots, whatever has focus; focus stays on the window it was on. Returns
  /// false if either window isn't in the list or they are the same window.
  @discardableResult
  package mutating func swap(_ first: WindowID, with second: WindowID) -> Bool {
    guard first != second, let firstIndex = windows.firstIndex(of: first),
      let secondIndex = windows.firstIndex(of: second)
    else { return false }
    swapSlots(firstIndex, secondIndex)
    return true
  }
}
