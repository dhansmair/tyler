import CoreGraphics

struct Bound<L: Layout>: BoundLayout {
  let layout: L
  let state: WritableKeyPath<LayoutStates, L.State>

  var scrolls: Bool { false }

  func frames(
    of windows: [WindowID], states: LayoutStates, view: Int, in area: CGRect, gaps: LayoutGaps
  ) -> [CGRect] {
    layout.frames(of: windows, state: states[keyPath: state], in: area, gaps: gaps)
  }

  func states(
    after resize: ResizedWindow, of windows: [WindowID], states: LayoutStates, in area: CGRect,
    gaps: LayoutGaps
  ) -> LayoutStates? {
    layout.state(
      after: resize, of: windows, state: states[keyPath: state], in: area, gaps: gaps
    ).map { updated in
      var states = states
      states[keyPath: state] = updated
      return states
    }
  }

  func restingViews(
    of windows: [WindowID], states: LayoutStates, in area: CGRect, gaps: LayoutGaps
  ) -> [RestingView] {
    []
  }

  func fittedView(
    of windows: [WindowID], states: LayoutStates, from view: Int, showing focused: Int?
  ) -> Int? {
    nil
  }

  func scrollTarget(
    startingAt index: Int, of windows: [WindowID], states: LayoutStates, focused: Int?
  ) -> ScrollTarget? {
    nil
  }
}
