import CoreGraphics

/// The workspaces of one display, side by side in a row like pages. Exactly one is current (on
/// screen) and the others are parked. A window belongs to at most one workspace.
public struct WorkspaceStack: Equatable, Sendable {
  /// How many workspaces a stack has unless the config file says otherwise.
  public static let defaultCount = 4

  public private(set) var workspaces: [Workspace]
  /// 0-based index of the workspace on screen.
  public private(set) var currentIndex = 0

  /// A stack of `count` empty workspaces (at least one), starting on the first.
  public init(count: Int = WorkspaceStack.defaultCount) {
    workspaces = Array(repeating: Workspace(), count: max(1, count))
  }

  public var count: Int { workspaces.count }
  public var indices: Range<Int> { workspaces.indices }

  // `_modify` rather than `set`: a change such as `stack.current.resize(…)` then happens in
  // place. With `set`, the copy being changed shares its window list with the one still in
  // `workspaces`, so every change copied the list (once per drag step, once per workspace per
  // sync).

  public subscript(index: Int) -> Workspace {
    get { workspaces[index] }
    _modify { yield &workspaces[index] }
  }

  /// The workspace on screen.
  public var current: Workspace {
    get { workspaces[currentIndex] }
    _modify { yield &workspaces[currentIndex] }
  }

  /// The index of the workspace holding `windowID`, if any.
  public func index(containing windowID: WindowID) -> Int? {
    workspaces.firstIndex { $0.contains(windowID) }
  }

  /// Every window on any workspace.
  public var allWindows: Set<WindowID> {
    Set(workspaces.flatMap(\.windows))
  }

  /// Resolves a target to an index: `prev` and `next` wrap around, numbers are 1-based and
  /// `nil` when out of range.
  public func index(of target: WorkspaceTarget) -> Int? {
    switch target {
    case .prev: (currentIndex - 1 + count) % count
    case .next: (currentIndex + 1) % count
    case .number(let number): (1...count).contains(number) ? number - 1 : nil
    }
  }

  /// Makes the workspace at `index` current. Returns false if it is out of range.
  @discardableResult
  public mutating func select(_ index: Int) -> Bool {
    guard indices.contains(index) else { return false }
    currentIndex = index
    return true
  }

  /// Moves a window from its workspace to the one at `index`, where it is inserted after the
  /// focused window and becomes focused. Returns false if the window is on no workspace, already
  /// on that one, or the index is out of range.
  @discardableResult
  public mutating func move(_ windowID: WindowID, to index: Int) -> Bool {
    guard indices.contains(index), let source = self.index(containing: windowID), source != index
    else {
      return false
    }
    workspaces[source].remove(windowID)
    workspaces[index].insert(windowID)
    workspaces[index].setFocus(windowID)
    return true
  }

  /// Gives the stack `count` workspaces (at least one). New workspaces are added empty at the
  /// bottom. Removed ones hand their windows to the new last workspace, appended in order after
  /// its own; if the current workspace is removed, the new last one becomes current.
  public mutating func setCount(_ count: Int) {
    let count = max(1, count)
    guard count < workspaces.count else {
      workspaces += Array(repeating: Workspace(), count: count - workspaces.count)
      return
    }
    let removed = workspaces[count...].flatMap(\.windows)
    workspaces.removeSubrange(count...)
    for windowID in removed {
      workspaces[count - 1].append(windowID)
    }
    currentIndex = min(currentIndex, count - 1)
  }

  /// Changes the gaps of every workspace, keeping each one's layout and ratio.
  public mutating func setGaps(inner: CGFloat, outer: CGFloat) {
    for index in workspaces.indices {
      workspaces[index].setGaps(inner: inner, outer: outer)
    }
  }

  /// Records that `windowID` got focus, on whichever workspace holds it.
  @discardableResult
  public mutating func setFocus(_ windowID: WindowID) -> Bool {
    guard let index = index(containing: windowID) else { return false }
    return workspaces[index].setFocus(windowID)
  }
}
