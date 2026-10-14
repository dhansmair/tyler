import CoreGraphics

extension Transition {
  /// Takes over from a transition still under way, which was taking windows to `finals`: those
  /// `placements` moves go there instead, the others go on to where they were going, each from
  /// `frame(of:)`, where it is now.
  package init(
    handingOver finals: [Placement], to placements: [Placement],
    from frame: (WindowID) -> CGRect?, duration: Duration
  ) {
    let moved = Set(placements.map(\.id))
    let targets = finals.filter { !moved.contains($0.id) } + placements
    let current = targets.compactMap { target in
      frame(target.id).map { Placement(id: target.id, frame: $0) }
    }
    self.init(retiling: current, to: targets, duration: duration)
  }

  /// Where each window taking part starts, at the size it has there.
  package var startFrames: [WindowID: CGRect] {
    let sizes = Dictionary(
      finals.map { ($0.id, $0.frame.size) }, uniquingKeysWith: { first, _ in first })
    var frames: [WindowID: CGRect] = [:]
    for track in tracks {
      guard let size = track.sizes?.start ?? sizes[track.id] else { continue }
      frames[track.id] = CGRect(origin: track.start, size: size)
    }
    return frames
  }
}
