import CoreGraphics

/// An ordered list of tiled windows, xmonad style: the first window is the master, every window
/// has a clear next and previous (wrapping around), and the layout turns list order into frames.
package struct Workspace: Equatable, Sendable {
  /// Every window of the workspace, in order. A flagged one takes no slot and keeps its place.
  package private(set) var members: [WindowID] = []
  private var flags: [WindowID: MemberFlags] = [:]
  /// Where each floating member was when its workspace last left the screen: where it comes back.
  private var floatingFrames: [WindowID: CGRect] = [:]
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

  package func tiles(_ windowID: WindowID) -> Bool {
    windows.contains(windowID)
  }

  /// Whether the window is seen with this workspace: tiled, or floating while its app isn't
  /// hidden.
  package func shows(_ windowID: WindowID) -> Bool {
    tiles(windowID) || flags[windowID] == .floating
  }

  package func flags(of windowID: WindowID) -> MemberFlags {
    flags[windowID] ?? []
  }

  /// The members whose app is hidden, in order.
  package var hidden: [WindowID] { members(flagged: .hidden) }

  /// The members the user floated, in order, whether their app is hidden or not.
  package var floating: [WindowID] { members(flagged: .floating) }

  /// The floating members that can be seen: their app isn't hidden.
  package var shownFloating: [WindowID] {
    flags.isEmpty ? [] : members.filter { flags[$0] == .floating }
  }

  package func floatingFrame(of windowID: WindowID) -> CGRect? {
    floatingFrames[windowID]
  }

  private func members(flagged flag: MemberFlags) -> [WindowID] {
    flags.isEmpty ? [] : members.filter { flags[$0]?.contains(flag) == true }
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

  /// Adds a member of `other` at the end of the list, with its flags and where it floats.
  package mutating func append(member windowID: WindowID, of other: Workspace) {
    let memberFlags = other.flags(of: windowID)
    guard !memberFlags.isEmpty else {
      append(windowID)
      return
    }
    insert(windowID, flagged: memberFlags, before: nil)
    floatingFrames[windowID] = other.floatingFrames[windowID]
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
      floatingFrames[windowID] = nil
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
  /// place in tall's main section), so it comes back as it was. A floating window can be hidden
  /// too, and floats again when it is shown.
  @discardableResult
  package mutating func hide(_ windowID: WindowID) -> Bool {
    if windows.contains(windowID) { return takeSlot(of: windowID, flag: .hidden) }
    guard flags[windowID] == .floating else { return false }
    flags[windowID]?.insert(.hidden)
    return true
  }

  /// A hidden window takes its slot again, in its place in the list, or floats again.
  @discardableResult
  package mutating func show(_ windowID: WindowID) -> Bool {
    clear(.hidden, of: windowID)
  }

  /// The user takes the window out of tiling: it stays a member, in its place, without a slot,
  /// and keeps its layout state as a hidden window does.
  @discardableResult
  package mutating func float(_ windowID: WindowID) -> Bool {
    takeSlot(of: windowID, flag: .floating)
  }

  /// A floating window takes its slot again, in its place in the list.
  @discardableResult
  package mutating func tile(_ windowID: WindowID) -> Bool {
    guard clear(.floating, of: windowID) else { return false }
    floatingFrames[windowID] = nil
    return true
  }

  /// Remembers where the floating members among `placements` are, as their workspace leaves the
  /// screen, so they come back there.
  package mutating func rememberFloatingFrames(_ placements: [Placement]) {
    for placement in placements where flags[placement.id]?.contains(.floating) == true {
      floatingFrames[placement.id] = placement.frame
    }
  }

  /// Adds a flagged window before the member `follower`, or at the end.
  package mutating func insert(
    _ windowID: WindowID, flagged memberFlags: MemberFlags, before follower: WindowID?
  ) {
    guard !holds(windowID), !memberFlags.isEmpty else { return }
    flags[windowID] = memberFlags
    members.insert(windowID, at: follower.flatMap(members.firstIndex) ?? members.count)
  }

  private mutating func takeSlot(of windowID: WindowID, flag: MemberFlags) -> Bool {
    guard let index = windows.firstIndex(of: windowID) else { return false }
    flags[windowID, default: []].insert(flag)
    refreshWindows()
    vacate(windowID, slotIndex: index)
    return true
  }

  private mutating func clear(_ flag: MemberFlags, of windowID: WindowID) -> Bool {
    guard flags[windowID]?.contains(flag) == true else { return false }
    flags[windowID]?.remove(flag)
    if flags[windowID]?.isEmpty == true { flags[windowID] = nil }
    refreshWindows()
    refitView()
    return true
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

  /// Makes `eligible` exactly the set of members that aren't hidden and `hiding` the set of
  /// hidden ones. Windows in neither are dropped, the others keep their order and their flags.
  /// New ones are inserted as a block after the focused window in the order given, except those
  /// in `floating`, which join floating at the end. Returns whether anything changed.
  @discardableResult
  package mutating func sync(
    eligible: [WindowID], hiding: Set<WindowID> = [], floating: Set<WindowID> = []
  ) -> Bool {
    let wanted = Set(eligible)
    var changed = false
    for windowID in hidden where !hiding.contains(windowID) {
      changed = true
      if !wanted.contains(windowID) || !show(windowID) { remove(windowID) }
    }
    for windowID in members
    where hiding.contains(windowID) && !flags(of: windowID).contains(.hidden) {
      hide(windowID)
      changed = true
    }
    for windowID in members where !wanted.contains(windowID) && !hiding.contains(windowID) {
      remove(windowID)
      changed = true
    }
    var insertionPoint = insertionIndex
    for windowID in eligible where !holds(windowID) {
      if floating.contains(windowID) {
        insert(windowID, flagged: .floating, before: nil)
      } else {
        place(windowID, atSlotIndex: insertionPoint)
        insertionPoint += 1
      }
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

  /// The two windows trade places in the list; flagged members stay where they are.
  mutating func swapSlots(_ first: Int, _ second: Int) {
    if let firstPosition = members.firstIndex(of: windows[first]),
      let secondPosition = members.firstIndex(of: windows[second])
    {
      members.swapAt(firstPosition, secondPosition)
    }
    refreshWindows()
    refitView()
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
