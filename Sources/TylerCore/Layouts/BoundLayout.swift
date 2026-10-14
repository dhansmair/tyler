import CoreGraphics

/// A layout bound to its field of `LayoutStates`, so a workspace can use the active layout
/// without knowing the type of its state. Only a scrolling layout answers the view's questions.
protocol BoundLayout {
  var scrolls: Bool { get }

  func frames(
    of windows: [WindowID], states: LayoutStates, view: Int, in area: CGRect, gaps: LayoutGaps
  ) -> [CGRect]

  func states(
    after resize: ResizedWindow, of windows: [WindowID], states: LayoutStates, in area: CGRect,
    gaps: LayoutGaps
  ) -> LayoutStates?

  func restingViews(
    of windows: [WindowID], states: LayoutStates, in area: CGRect, gaps: LayoutGaps
  ) -> [RestingView]

  func fittedView(
    of windows: [WindowID], states: LayoutStates, from view: Int, showing focused: Int?
  ) -> Int?

  func scrollTarget(
    startingAt index: Int, of windows: [WindowID], states: LayoutStates, focused: Int?
  ) -> ScrollTarget?
}
