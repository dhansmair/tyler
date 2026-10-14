import CoreGraphics

/// The workspaces of one display, side by side in a row like pages. Exactly one is current (on
/// screen) and the others are parked. A window belongs to at most one workspace.
///
/// Each workspace has a number, the one commands and the menu bar use. Numbers are global across
/// displays, so a row's numbers need not start at 1 or be consecutive (a second display may hold
/// 5 to 8); they always ascend from left to right.
package struct WorkspaceRow: Equatable, Sendable {
  /// How many workspaces a row has unless the config file says otherwise.
  package static let defaultCount = 4

  package private(set) var workspaces: [Workspace]
  /// The number of each workspace, ascending, in step with `workspaces`.
  package private(set) var numbers: [Int]
  /// 0-based index of the workspace on screen.
  package private(set) var currentIndex = 0

  /// A row of `count` empty workspaces (at least one), numbered from 1, starting on the first.
  package init(count: Int = WorkspaceRow.defaultCount) {
    self.init(numbers: Array(1...max(1, count)))
  }

  /// A row of empty workspaces with these numbers (sorted, without repeats; workspace 1 alone
  /// when empty) and `layout`, starting on the first.
  package init(numbers: [Int], layout: LayoutKind = .tall) {
    self.numbers = Self.normalized(numbers)
    workspaces = Array(repeating: Workspace(layout: layout), count: self.numbers.count)
  }

  private static func normalized(_ numbers: [Int]) -> [Int] {
    let sorted = Array(Set(numbers)).sorted()
    return sorted.isEmpty ? [1] : sorted
  }

  package var count: Int { workspaces.count }
  package var indices: Range<Int> { workspaces.indices }

  // `_modify` rather than `set`: a change such as `row.current.resize(…)` then happens in
  // place. With `set`, the copy being changed shares its window list with the one still in
  // `workspaces`, so every change copied the list (once per drag step, once per workspace per
  // sync).

  package subscript(index: Int) -> Workspace {
    get { workspaces[index] }
    _modify { yield &workspaces[index] }
  }

  /// The workspace on screen.
  package var current: Workspace {
    get { workspaces[currentIndex] }
    _modify { yield &workspaces[currentIndex] }
  }

  /// The number of the workspace at `index`.
  package func number(at index: Int) -> Int { numbers[index] }

  /// The index of the workspace numbered `number`, if the row has it.
  package func index(ofNumber number: Int) -> Int? {
    numbers.firstIndex(of: number)
  }

  /// The index of the workspace holding `windowID`, if any.
  package func index(containing windowID: WindowID) -> Int? {
    workspaces.firstIndex { $0.contains(windowID) }
  }

  /// Every window on any workspace.
  package var allWindows: Set<WindowID> {
    Set(workspaces.flatMap(\.windows))
  }

  /// Resolves a target to an index: `prev` and `next` wrap around, and a number is `nil` when
  /// the row has no workspace with it.
  package func index(of target: WorkspaceTarget) -> Int? {
    switch target {
    case .prev: currentIndex.stepped(by: -1, wrappingAt: count)
    case .next: currentIndex.stepped(by: 1, wrappingAt: count)
    case .number(let number): index(ofNumber: number)
    }
  }

  /// Makes the workspace at `index` current. Returns false if it is out of range.
  @discardableResult
  package mutating func select(_ index: Int) -> Bool {
    guard indices.contains(index) else { return false }
    currentIndex = index
    return true
  }

  /// Moves a window from its workspace to the one at `index`, where it is inserted after the
  /// focused window and becomes focused, keeping its strip size (a `quarter` arrives as `half`).
  /// Returns false if the window is on no workspace, already on that one, or the index is out of
  /// range.
  @discardableResult
  package mutating func move(_ windowID: WindowID, to index: Int) -> Bool {
    guard indices.contains(index), let source = self.index(containing: windowID), source != index
    else {
      return false
    }
    let states = workspaces[source].layoutStates
    workspaces[source].remove(windowID)
    workspaces[index].insert(windowID)
    workspaces[index].adopt(windowID, from: states)
    workspaces[index].setFocus(windowID)
    return true
  }

  /// Gives the row `count` workspaces (at least one), keeping the first ones' numbers and
  /// numbering new ones on from the last. See `setNumbers` for what happens to the windows.
  package mutating func setCount(_ count: Int) {
    let count = max(1, count)
    let last = numbers[numbers.count - 1]
    let added = count > numbers.count ? Array(last + 1...last + count - numbers.count) : []
    setNumbers(Array(numbers.prefix(count)) + added)
  }

  /// Gives the row the workspaces with these numbers (sorted, without repeats; workspace 1 alone
  /// when empty). Workspaces that keep their number keep their windows; new ones are empty.
  /// Removed ones hand their windows to the new last workspace, appended in order after its own.
  /// If the current workspace is removed, the new last one becomes current. New workspaces get
  /// `newLayout`.
  package mutating func setNumbers(_ newNumbers: [Int], newLayout: LayoutKind = .tall) {
    let newNumbers = Self.normalized(newNumbers)
    let currentNumber = numbers[currentIndex]
    let byNumber = Dictionary(uniqueKeysWithValues: zip(numbers, workspaces))
    let removed = numbers.filter { !newNumbers.contains($0) }.flatMap {
      byNumber[$0]?.windows ?? []
    }
    workspaces = newNumbers.map { byNumber[$0] ?? Workspace(layout: newLayout) }
    numbers = newNumbers
    for windowID in removed {
      workspaces[workspaces.count - 1].append(windowID)
    }
    currentIndex = numbers.firstIndex(of: currentNumber) ?? numbers.count - 1
  }

  /// Adds `workspace` as number `number`, in number order; the current workspace stays current.
  /// Returns false, changing nothing, if the row already has that number.
  @discardableResult
  package mutating func insert(_ workspace: Workspace, number: Int) -> Bool {
    guard !numbers.contains(number) else { return false }
    let index = numbers.firstIndex { $0 > number } ?? numbers.count
    numbers.insert(number, at: index)
    workspaces.insert(workspace, at: index)
    if index <= currentIndex { currentIndex += 1 }
    return true
  }

  /// Takes out the workspace numbered `number`, with its windows. If it was current, the next one
  /// becomes current, or the previous one at the end of the row. Returns `nil`, changing nothing,
  /// if the row has no such workspace or it is the row's only one.
  package mutating func remove(number: Int) -> Workspace? {
    guard count > 1, let index = index(ofNumber: number) else { return nil }
    numbers.remove(at: index)
    let workspace = workspaces.remove(at: index)
    if index < currentIndex || currentIndex == count { currentIndex -= 1 }
    return workspace
  }

  /// Records that `windowID` got focus, on whichever workspace holds it.
  @discardableResult
  package mutating func setFocus(_ windowID: WindowID) -> Bool {
    guard let index = index(containing: windowID) else { return false }
    return workspaces[index].setFocus(windowID)
  }
}

extension WorkspaceTarget {
  /// Which way the row scrolls to go from the workspace at `source` to the one at `index`:
  /// `prev` and `next` go their way even when they wrap; a number goes along the row.
  package func direction(from source: Int, to index: Int) -> ScrollDirection {
    switch self {
    case .prev: .prev
    case .next: .next
    case .number: index > source ? .next : .prev
    }
  }
}
