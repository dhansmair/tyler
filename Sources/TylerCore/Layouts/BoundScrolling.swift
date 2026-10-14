import CoreGraphics

struct BoundScrolling<L: ScrollingLayout>: BoundLayout {
  let layout: L
  let state: WritableKeyPath<LayoutStates, L.State>

  var scrolls: Bool { true }

  func frames(
    of windows: [WindowID], states: LayoutStates, view: Int, in area: CGRect, gaps: LayoutGaps
  ) -> [CGRect] {
    layout.frames(
      of: windows, state: states[keyPath: state], startingAt: view, in: area, gaps: gaps)
  }

  func states(
    after resize: ResizedWindow, of windows: [WindowID], states: LayoutStates, in area: CGRect,
    gaps: LayoutGaps
  ) -> LayoutStates? {
    Bound(layout: layout, state: state).states(
      after: resize, of: windows, states: states, in: area, gaps: gaps)
  }

  func restingViews(
    of windows: [WindowID], states: LayoutStates, in area: CGRect, gaps: LayoutGaps
  ) -> [RestingView] {
    layout.restingViews(of: windows, state: states[keyPath: state], in: area, gaps: gaps)
  }

  func fittedView(
    of windows: [WindowID], states: LayoutStates, from view: Int, showing focused: Int?
  ) -> Int? {
    layout.fittedView(
      of: windows, state: states[keyPath: state], from: view, showing: focused)
  }

  func scrollTarget(
    startingAt index: Int, of windows: [WindowID], states: LayoutStates, focused: Int?
  ) -> ScrollTarget? {
    layout.scrollTarget(
      startingAt: index, of: windows, state: states[keyPath: state], focused: focused)
  }
}
