import CoreGraphics

/// A layout wider than its area, seen through a view that scrolls. A view is named by the index of
/// the window at its left edge.
package protocol ScrollingLayout: Layout {
  func frames(
    of windows: [WindowID], state: State, startingAt view: Int, in area: CGRect, gaps: LayoutGaps
  ) -> [CGRect]

  /// Left to right: where a swipe can settle.
  func restingViews(
    of windows: [WindowID], state: State, in area: CGRect, gaps: LayoutGaps
  ) -> [RestingView]

  /// `view` moved the least that shows window `focused` whole.
  func fittedView(of windows: [WindowID], state: State, from view: Int, showing focused: Int?)
    -> Int

  /// The view starting as near window `index` as the layout's end allows, and where focus goes:
  /// to the nearest window in view if the focused one isn't. `nil` if there is no such window.
  func scrollTarget(
    startingAt index: Int, of windows: [WindowID], state: State, focused: Int?
  ) -> ScrollTarget?
}

extension ScrollingLayout {
  package func frames(
    of windows: [WindowID], state: State, in area: CGRect, gaps: LayoutGaps
  ) -> [CGRect] {
    frames(of: windows, state: state, startingAt: 0, in: area, gaps: gaps)
  }
}
