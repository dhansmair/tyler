import CoreGraphics

extension Workspace {
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
}
