import CoreGraphics

/// The view of a scrolling layout.
extension Workspace {
  package var scrolls: Bool { layout.bound.scrolls }

  /// One place the view can rest, where a swipe can settle.
  package struct View: Equatable, Sendable {
    /// How far the view is scrolled from the first one, in points.
    package let offset: CGFloat
    package let firstVisible: WindowID
    package let arrangement: [Placement]
  }

  /// None in a layout that doesn't scroll.
  package func views(in area: CGRect, gaps: LayoutGaps) -> [View] {
    let bound = layout.bound
    return bound.restingViews(of: windows, states: layoutStates, in: area, gaps: gaps).map {
      view in
      let frames = bound.frames(
        of: windows, states: layoutStates, view: view.firstVisible, in: area, gaps: gaps)
      return View(
        offset: view.offset, firstVisible: windows[view.firstVisible],
        arrangement: zip(windows, frames).map { Placement(id: $0, frame: $1) })
    }
  }

  /// Scrolls so that the view starts at `windowID`, or as near as the layout's end allows. If the
  /// focused window scrolled out of view, focus moves to the nearest window in view. Returns
  /// whether focus moved.
  @discardableResult
  package mutating func scroll(toFirstVisible windowID: WindowID) -> Bool {
    guard let index = windows.firstIndex(of: windowID),
      let target = layout.bound.scrollTarget(
        startingAt: index, of: windows, states: layoutStates, focused: focusedIndex)
    else { return false }
    firstVisible = windows[target.firstVisible]
    guard let newFocus = target.focused, newFocus != focusedIndex else { return false }
    focused = windows[newFocus]
    return true
  }

  /// Moves the view the least that shows the focused window whole. A layout that doesn't scroll
  /// leaves the view alone, so a scrolling layout finds it where it left it.
  mutating func refitView() {
    guard !windows.isEmpty else {
      firstVisible = nil
      return
    }
    guard
      let fitted = layout.bound.fittedView(
        of: windows, states: layoutStates, from: viewIndex, showing: focusedIndex)
    else { return }
    firstVisible = windows[fitted]
  }
}
