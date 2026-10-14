import CoreGraphics

/// An ordered list of tiled windows, xmonad style: the first window is the master, every window
/// has a clear next and previous (wrapping around), and the layout turns list order into frames.
package struct Workspace: Equatable, Sendable {
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
    guard let index = windows.firstIndex(of: windowID) else { return false }
    layoutStates.remove(windowID, from: windows)
    windows.remove(at: index)
    let successor = windows.isEmpty ? nil : windows[min(index, windows.count - 1)]
    if focused == windowID { focused = successor }
    if firstVisible == windowID { firstVisible = successor }
    refitView()
    return true
  }

  /// Makes `eligible` exactly the set of tiled windows. Windows no longer eligible are dropped,
  /// the others keep their order, and new ones are inserted as a block after the focused window
  /// in the order given. Returns whether anything changed.
  @discardableResult
  package mutating func sync(eligible: [WindowID]) -> Bool {
    let wanted = Set(eligible)
    var changed = false
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

  /// The window that `windowID` would swap with if it were dropped at `point`: the one whose
  /// slot is under the point. Nothing while the point is still in `windowID`'s own slot (in
  /// `full`, that is everywhere), in a gap, or outside the tiled area.
  package func dropTarget(
    for windowID: WindowID, at point: CGPoint, on display: DisplayInfo, gaps: LayoutGaps
  ) -> WindowID? {
    Self.dropTarget(for: windowID, at: point, among: placements(on: display, gaps: gaps))
  }

  /// `dropTarget(for:at:on:gaps:)` for placements already worked out, so a caller that needs them
  /// anyway lays the workspace out once.
  package static func dropTarget(
    for windowID: WindowID, at point: CGPoint, among placements: [Placement]
  ) -> WindowID? {
    guard let own = placements.first(where: { $0.id == windowID }), !own.frame.contains(point)
    else { return nil }
    return placements.first { $0.id != windowID && $0.frame.contains(point) }?.id
  }

  /// Where `windowID`, coming from another workspace, goes in if it is dropped at `point`: the
  /// place in the list whose slot, with the window in it there, is under the point. So the slot
  /// a preview leaves open (see `arriving(_:at:)`) is always the one under the pointer. `nil` in
  /// a gap or outside the tiled area.
  package func arrivalIndex(
    of windowID: WindowID, at point: CGPoint, on display: DisplayInfo, gaps: LayoutGaps
  ) -> Int? {
    (0...count).first { index in
      arriving(windowID, at: index).placements(on: display, gaps: gaps).contains {
        $0.id == windowID && $0.frame.contains(point)
      }
    }
  }

  /// This workspace with `windowID` gone in at `index` of the list (the window there and those
  /// after it move one later), or last if `index` is past the end.
  package func arriving(_ windowID: WindowID, at index: Int) -> Workspace {
    var copy = self
    copy.insert(windowID, before: windows.indices.contains(index) ? windows[index] : nil)
    return copy
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

  /// Where a window joining the list goes: right after the focused one, or at the end.
  private var insertionIndex: Int {
    focusedIndex.map { $0 + 1 } ?? windows.count
  }
}
