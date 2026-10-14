import CoreGraphics

/// Windows put at `start`, moved along `tracks` from `startProgress` to `endProgress` (taking at
/// least `minimumDuration`), and placed at `finals` at the end, whether the transition runs to
/// it or is cut short.
package struct Transition: Equatable, Sendable {
  package var start: [Placement]
  package var tracks: [Track]
  package var finals: [Placement]
  package var startProgress: Double
  package var endProgress: Double
  package var minimumDuration: Duration

  package init(
    start: [Placement] = [], tracks: [Track], finals: [Placement], startProgress: Double = 0,
    endProgress: Double = 1, minimumDuration: Duration = .zero
  ) {
    self.start = start
    self.tracks = tracks
    self.finals = finals
    self.startProgress = startProgress
    self.endProgress = endProgress
    self.minimumDuration = minimumDuration
  }
}

extension SlidePlan {
  package var transition: Transition {
    Transition(start: start, tracks: tracks, finals: finals)
  }
}

extension ScrollPlan {
  package var transition: Transition {
    Transition(start: start, tracks: tracks, finals: finals)
  }
}
