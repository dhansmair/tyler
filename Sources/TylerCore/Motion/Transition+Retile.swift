import CoreGraphics

extension Transition {
  /// Windows going from their slots in `before` to their slots in `after` on the same display,
  /// each in a straight line, changing its size along the way; those whose slot stays the same
  /// take no part.
  package init(retiling before: [Placement], to after: [Placement], duration: Duration) {
    let old = Dictionary(before.map { ($0.id, $0.frame) }, uniquingKeysWith: { first, _ in first })
    var tracks: [Track] = []
    var finals: [Placement] = []
    for placement in after {
      guard let previous = old[placement.id], previous != placement.frame else { continue }
      let sizes =
        previous.size == placement.frame.size
        ? nil : Track.Sizes(start: previous.size, end: placement.frame.size)
      tracks.append(
        Track(id: placement.id, start: previous.origin, end: placement.frame.origin, sizes: sizes))
      finals.append(placement)
    }
    self.init(tracks: tracks, finals: finals, duration: duration)
  }
}
