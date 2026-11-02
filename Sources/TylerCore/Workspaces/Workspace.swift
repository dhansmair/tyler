import CoreGraphics

/// An ordered list of tiled windows, xmonad style: the first window is the master, every window
/// has a clear next and previous (wrapping around), and the layout turns list order into frames.
package struct Workspace: Equatable, Sendable {
  package private(set) var windows: [WindowID] = [] {
    didSet { placeHiddenMembers() }
  }
  /// Every window of the workspace in order: the tiled ones and, between them, the hidden ones.
  package private(set) var members: [WindowID] = []
  /// Members that take no slot, as their app is hidden. Each keeps its place before the member
  /// that followed it, so it comes back there.
  package private(set) var hidden: Set<WindowID> = []
  /// The tiled window that `focus` and `swap` are relative to.
  package internal(set) var focused: WindowID?
  package var layout: LayoutKind {
    didSet { if layout != oldValue { refitView() } }
  }
  package internal(set) var layoutStates: LayoutStates
  /// The window at the left edge of a scrolling layout's view. Kept in every layout, so a
  /// scrolling layout comes back to the view it had.
  package internal(set) var firstVisible: WindowID?

  package init(layout: LayoutKind = .tall, layoutStates: LayoutStates = LayoutStates()) {
    self.layout = layout
    self.layoutStates = layoutStates
  }

  package var count: Int { windows.count }

  package func contains(_ windowID: WindowID) -> Bool {
    windows.contains(windowID)
  }

  /// The 1-based position in the list; 1 is the master.
  package func slot(of windowID: WindowID) -> Int? {
    windows.firstIndex(of: windowID).map { $0 + 1 }
  }

  // MARK: - Membership

  /// Adds a window right after the focused one, or at the end if nothing is focused.
  @discardableResult
  package mutating func insert(_ windowID: WindowID) -> Bool {
    guard !contains(windowID) else { return false }
    windows.insert(windowID, at: insertionIndex)
    refitView()
    return true
  }

  /// Adds a window at the end of the list, whatever has focus.
  @discardableResult
  package mutating func append(_ windowID: WindowID) -> Bool {
    guard !contains(windowID) else { return false }
    windows.append(windowID)
    refitView()
    return true
  }

  /// Adds a window just before `other` (it takes `other`'s place, and `other` moves one later),
  /// or at the end if `other` is `nil` or not in the list.
  @discardableResult
  package mutating func insert(_ windowID: WindowID, before other: WindowID?) -> Bool {
    guard !contains(windowID) else { return false }
    let index = other.flatMap { windows.firstIndex(of: $0) } ?? windows.count
    windows.insert(windowID, at: index)
    refitView()
    return true
  }

  /// Removes a window. If it had focus, focus moves to the window that took its place (or the
  /// new last window), and so does the strip's view if it started at that window. A `quarter`
  /// window's column mate goes back to `half`.
  @discardableResult
  package mutating func remove(_ windowID: WindowID) -> Bool {
    if hidden.remove(windowID) != nil {
      members.removeAll { $0 == windowID }
      return true
    }
    return remove(tiled: windowID)
  }

  private mutating func remove(tiled windowID: WindowID) -> Bool {
    guard let index = windows.firstIndex(of: windowID) else { return false }
    layoutStates.remove(windowID, from: windows)
    windows.remove(at: index)
    let successor = windows.isEmpty ? nil : windows[min(index, windows.count - 1)]
    if focused == windowID { focused = successor }
    if firstVisible == windowID { firstVisible = successor }
    refitView()
    return true
  }

  /// The window stays a member but takes no slot, and leaves the layout as a removed window does.
  @discardableResult
  package mutating func hide(_ windowID: WindowID) -> Bool {
    guard contains(windowID) else { return false }
    hidden.insert(windowID)
    return remove(tiled: windowID)
  }

  /// A hidden window takes a slot again, before the tiled window that follows it.
  @discardableResult
  package mutating func show(_ windowID: WindowID) -> Bool {
    guard hidden.remove(windowID) != nil, let place = members.firstIndex(of: windowID) else {
      return false
    }
    let follower = members[place...].first(where: contains)
    insert(windowID, before: follower)
    return true
  }

  /// Rebuilds `members` from the tiled order, each hidden member before the one it was before.
  private mutating func placeHiddenMembers() {
    guard !hidden.isEmpty else {
      members = windows
      return
    }
    var rebuilt = windows
    var follower: WindowID?
    for member in members.reversed() {
      if hidden.contains(member) {
        rebuilt.insert(member, at: follower.flatMap(rebuilt.firstIndex) ?? rebuilt.count)
        follower = member
      } else if rebuilt.contains(member) {
        follower = member
      }
    }
    members = rebuilt
  }

  /// Makes `eligible` exactly the set of tiled windows and `hiding` the set of hidden members.
  /// Windows in neither are dropped, the others keep their order, and new ones are inserted as a
  /// block after the focused window in the order given. Returns whether anything changed.
  @discardableResult
  package mutating func sync(eligible: [WindowID], hiding: Set<WindowID> = []) -> Bool {
    let wanted = Set(eligible)
    var changed = false
    for windowID in hidden where !hiding.contains(windowID) {
      changed = true
      if !wanted.contains(windowID) || !show(windowID) { remove(windowID) }
    }
    for windowID in windows where hiding.contains(windowID) {
      hide(windowID)
      changed = true
    }
    for windowID in windows where !wanted.contains(windowID) {
      remove(windowID)
      changed = true
    }
    var insertionPoint = insertionIndex
    for windowID in eligible where !contains(windowID) {
      windows.insert(windowID, at: insertionPoint)
      insertionPoint += 1
      changed = true
    }
    refitView()
    return changed
  }

  // MARK: - Focus and order

  /// Records that the operating system focused `windowID`. Windows that aren't tiled are
  /// ignored, so `focus next` stays relative to the last tiled window you used.
  @discardableResult
  package mutating func setFocus(_ windowID: WindowID) -> Bool {
    guard contains(windowID), focused != windowID else { return false }
    focused = windowID
    refitView()
    return true
  }

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
    windows.swapAt(current, other)
    refitView()
    return true
  }

  /// Swaps two windows' slots, whatever has focus; focus stays on the window it was on. Returns
  /// false if either window isn't in the list or they are the same window.
  @discardableResult
  package mutating func swap(_ first: WindowID, with second: WindowID) -> Bool {
    guard first != second, let firstIndex = windows.firstIndex(of: first),
      let secondIndex = windows.firstIndex(of: second)
    else { return false }
    windows.swapAt(firstIndex, secondIndex)
    refitView()
    return true
  }

  // MARK: - Layout

  /// Changes one layout's state, then fits the view to it, since the change may have moved the
  /// focused window out of view.
  @discardableResult
  package mutating func update<State: LayoutState, Result>(
    _ state: WritableKeyPath<LayoutStates, State>,
    _ change: (inout State, _ windows: [WindowID]) -> Result
  ) -> Result {
    let result = change(&layoutStates[keyPath: state], windows)
    refitView()
    return result
  }

  /// `windowID`, now in this workspace, brings its per-window layout state from `other`.
  mutating func adopt(_ windowID: WindowID, from other: LayoutStates) {
    guard contains(windowID) else { return }
    layoutStates.adopt(windowID, from: other)
    refitView()
  }

  /// Follows the user resizing `windowID` to `frame`: the layout moves the dividers whose edges
  /// were dragged. Returns whether the layout states changed.
  @discardableResult
  package mutating func resize(
    _ windowID: WindowID, to frame: CGRect, in area: CGRect, gaps: LayoutGaps
  ) -> Bool {
    guard let index = windows.firstIndex(of: windowID),
      let updated = layout.bound.states(
        after: ResizedWindow(index: index, frame: frame), of: windows, states: layoutStates,
        in: area, gaps: gaps),
      updated != layoutStates
    else { return false }
    layoutStates = updated
    return true
  }

  /// Switches to the layout after this one in `cycle` (see `LayoutKind.next(in:)`).
  package mutating func cycleLayout(through cycle: [LayoutKind] = LayoutKind.defaultCycle) {
    layout = layout.next(in: cycle)
  }

  /// Every window's frame, in list order. In the strip layout, windows out of view get frames
  /// off the area.
  package func arrangement(in area: CGRect, gaps: LayoutGaps) -> [Placement] {
    let frames = layout.bound.frames(
      of: windows, states: layoutStates, view: viewIndex, in: area, gaps: gaps)
    return zip(windows, frames).map { Placement(id: $0, frame: $1) }
  }

  /// The windows in view and where they go, in list order. That is every window, except in the
  /// strip layout.
  package func placements(on display: DisplayInfo, gaps: LayoutGaps) -> [Placement] {
    arrangement(in: display.visibleFrame, gaps: gaps).filter { display.shows($0.frame) }
  }

  /// The windows out of view: only in the strip layout.
  package func offView(on display: DisplayInfo, gaps: LayoutGaps) -> [WindowID] {
    arrangement(in: display.visibleFrame, gaps: gaps).filter { !display.shows($0.frame) }.map(\.id)
  }

  var viewIndex: Int {
    firstVisible.flatMap(windows.firstIndex(of:)) ?? 0
  }

  var focusedIndex: Int? {
    focused.flatMap { windows.firstIndex(of: $0) }
  }

  /// Moves the window at `index` to `destination`, the others closing up behind it.
  mutating func moveWindow(at index: Int, to destination: Int) {
    windows.insert(windows.remove(at: index), at: destination)
    refitView()
  }

  /// Where a window joining the list goes: right after the focused one, or at the end. In `tall`
  /// it goes into the stack, never into the master section.
  private var insertionIndex: Int {
    let afterFocused = focusedIndex.map { $0 + 1 } ?? windows.count
    return layout == .tall ? max(afterFocused, mainSectionCount) : afterFocused
  }
}
