import CoreGraphics

/// An ordered list of tiled windows, xmonad style: the first window is the master, every window
/// has a clear next and previous (wrapping around), and the layout turns list order into frames.
package struct Workspace: Equatable, Sendable {
  /// Every window of the workspace, in order. A flagged one takes no slot and keeps its place.
  package private(set) var members: [WindowID] = []
  private var flags: [WindowID: MemberFlags] = [:]
  /// The members without a flag, in order: what the layout places. Stored, so the layouts and
  /// each frame of a slide read it without work; `refreshWindows()` keeps it in step.
  package private(set) var windows: [WindowID] = []
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

  /// Whether the window is on this workspace, flagged or not.
  package func holds(_ windowID: WindowID) -> Bool {
    members.contains(windowID)
  }

  /// Whether the window takes a slot here.
  package func tiles(_ windowID: WindowID) -> Bool {
    windows.contains(windowID)
  }

  package func flags(of windowID: WindowID) -> MemberFlags {
    flags[windowID] ?? []
  }

  /// The members whose app is hidden, in order.
  package var hidden: [WindowID] {
    flags.isEmpty ? [] : members.filter { flags[$0]?.contains(.hidden) == true }
  }

  /// The 1-based position in the list; 1 is the master.
  package func slot(of windowID: WindowID) -> Int? {
    windows.firstIndex(of: windowID).map { $0 + 1 }
  }

  // MARK: - Membership

  /// Adds a window right after the focused one, or at the end if nothing is focused.
  @discardableResult
  package mutating func insert(_ windowID: WindowID) -> Bool {
    guard !holds(windowID) else { return false }
    place(windowID, atSlotIndex: insertionIndex)
    refitView()
    return true
  }

  /// Adds a window at the end of the list, whatever has focus.
  @discardableResult
  package mutating func append(_ windowID: WindowID) -> Bool {
    guard !holds(windowID) else { return false }
    place(windowID, atSlotIndex: windows.count)
    refitView()
    return true
  }

  /// Adds a window just before `other` (it takes `other`'s place, and `other` moves one later),
  /// or at the end if `other` is `nil` or not in the list.
  @discardableResult
  package mutating func insert(_ windowID: WindowID, before other: WindowID?) -> Bool {
    guard !holds(windowID) else { return false }
    let index = other.flatMap { windows.firstIndex(of: $0) } ?? windows.count
    place(windowID, atSlotIndex: index)
    refitView()
    return true
  }

  /// Removes a window. If it had focus, focus moves to the window that took its place (or the
  /// new last window), and so does the strip's view if it started at that window. A `quarter`
  /// window's column mate goes back to `half`.
  @discardableResult
  package mutating func remove(_ windowID: WindowID) -> Bool {
    if flags[windowID] != nil {
      // It leaves the layout states from the place it would take, as it kept its state there.
      layoutStates.remove(windowID, from: members.filter { flags[$0] == nil || $0 == windowID })
      flags[windowID] = nil
      members.removeAll { $0 == windowID }
      refreshWindows()
      return true
    }
    guard let index = windows.firstIndex(of: windowID) else { return false }
    layoutStates.remove(windowID, from: windows)
    members.removeAll { $0 == windowID }
    refreshWindows()
    vacate(windowID, slotIndex: index)
    return true
  }

  /// The window stays a member but takes no slot. It keeps its layout state (a strip size, its
  /// place in tall's main section), so it comes back as it was.
  @discardableResult
  package mutating func hide(_ windowID: WindowID) -> Bool {
    guard let index = windows.firstIndex(of: windowID) else { return false }
    flags[windowID, default: []].insert(.hidden)
    refreshWindows()
    vacate(windowID, slotIndex: index)
    return true
  }

  /// A hidden window takes a slot again, in its place in the list.
  @discardableResult
  package mutating func show(_ windowID: WindowID) -> Bool {
    guard flags[windowID]?.contains(.hidden) == true else { return false }
    flags[windowID]?.remove(.hidden)
    if flags[windowID]?.isEmpty == true { flags[windowID] = nil }
    refreshWindows()
    refitView()
    return true
  }

  /// Adds a hidden window before the member `follower`, or at the end.
  package mutating func insertHidden(_ windowID: WindowID, before follower: WindowID?) {
    guard !holds(windowID) else { return }
    flags[windowID, default: []].insert(.hidden)
    members.insert(windowID, at: follower.flatMap(members.firstIndex) ?? members.count)
  }

  /// Puts a new member where it takes the slot at `index`: right after the tiled window before
  /// it, so a flagged member stays before the window it came before.
  private mutating func place(_ windowID: WindowID, atSlotIndex index: Int) {
    let position = index == 0 ? 0 : (members.firstIndex(of: windows[index - 1]) ?? -1) + 1
    members.insert(windowID, at: position)
    refreshWindows()
  }

  private mutating func refreshWindows() {
    windows = flags.isEmpty ? members : members.filter { flags[$0] == nil }
  }

  /// The window that held the slot at `index` is gone from it: focus and the view move on to the
  /// window that took the slot, or to the new last window.
  private mutating func vacate(_ windowID: WindowID, slotIndex index: Int) {
    let successor = windows.isEmpty ? nil : windows[min(index, windows.count - 1)]
    if focused == windowID { focused = successor }
    if firstVisible == windowID { firstVisible = successor }
    refitView()
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
    for windowID in eligible where !holds(windowID) {
      place(windowID, atSlotIndex: insertionPoint)
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
    guard tiles(windowID), focused != windowID else { return false }
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

  /// The two windows trade places in the list; flagged members stay where they are.
  private mutating func swapSlots(_ first: Int, _ second: Int) {
    if let firstPosition = members.firstIndex(of: windows[first]),
      let secondPosition = members.firstIndex(of: windows[second])
    {
      members.swapAt(firstPosition, secondPosition)
    }
    refreshWindows()
    refitView()
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
    guard tiles(windowID) else { return }
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
    let windowID = windows[index]
    members.removeAll { $0 == windowID }
    refreshWindows()
    place(windowID, atSlotIndex: destination)
    refitView()
  }

  /// Where a window joining the list goes: right after the focused one, or at the end. In `tall`
  /// it goes into the stack, never into the master section.
  private var insertionIndex: Int {
    let afterFocused = focusedIndex.map { $0 + 1 } ?? windows.count
    return layout == .tall ? max(afterFocused, mainSectionCount) : afterFocused
  }
}
