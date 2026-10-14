/// What the windows do for one position of the fingers: `placements` first (windows coming out
/// of their parked spots or going back), then `nudges` along the tracks.
package struct SwipeStep: Equatable, Sendable {
  package var placements: [Placement] = []
  package var nudges: [Nudge] = []
}
