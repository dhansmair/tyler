/// How a swipe ends once the fingers lift.
package struct SwipeEnding: Equatable, Sendable {
  /// Where the swipe leaves the current workspace.
  package enum Destination: Equatable, Sendable {
    case stay
    case workspace(index: Int)
    case view(firstVisible: WindowID)
  }

  /// The slide that settles the windows, run part-way from where the swipe left them.
  package struct Settle: Equatable, Sendable {
    package let tracks: [Track]
    package let finals: [Placement]
    package let start: Double
    package let end: Double
    /// Going back to where the swipe began, which takes at least `SwipeSession.returnShare` of a
    /// whole slide.
    package let isReturn: Bool

    /// A slide of the whole way takes `slideDuration`.
    package func transition(slideDuration: Duration) -> Transition {
      Transition(
        tracks: tracks, finals: finals, startProgress: start, endProgress: end,
        minimumDuration: isReturn ? slideDuration * SwipeSession.returnShare : .zero)
    }
  }

  /// Placed before the slide: windows of a side the swipe hadn't brought out yet.
  package var placements: [Placement] = []
  package var settle: Settle?
  package var destination = Destination.stay
}
