import CoreGraphics

/// Windows put at `start`, moved along `tracks` from `startProgress` to `endProgress` (taking at
/// least `minimumDuration`), and placed at `finals` at the end, whether the transition runs to
/// it or is cut short. It takes `duration`, or a slide's when that is `nil`; zero places the
/// windows at `finals` at once.
package struct Transition: Equatable, Sendable {
  package var start: [Placement]
  package var tracks: [Track]
  package var finals: [Placement]
  package var startProgress: Double
  package var endProgress: Double
  package var minimumDuration: Duration
  package var duration: Duration?

  package init(
    start: [Placement] = [], tracks: [Track], finals: [Placement], startProgress: Double = 0,
    endProgress: Double = 1, minimumDuration: Duration = .zero, duration: Duration? = nil
  ) {
    self.start = start
    self.tracks = tracks
    self.finals = finals
    self.startProgress = startProgress
    self.endProgress = endProgress
    self.minimumDuration = minimumDuration
    self.duration = duration
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
