import CoreGraphics

/// How the strip's windows move when its view scrolls: worked out up front from where every
/// window is before and after, so a scroll or a trackpad pan can run it forwards, part-way, or
/// back. Windows out of view at both ends stay parked and take no part.
public struct ScrollPlan: Equatable, Sendable {
  /// Where the windows coming into view wait before they slide: resized for the view, off screen.
  public private(set) var start: [Placement] = []
  public private(set) var tracks: [Track] = []
  /// Where every window taking part ends up: in its slot, or parked if it left the view.
  public private(set) var finals: [Placement] = []
  /// Where every window taking part goes back to if the scroll is called off.
  public private(set) var returns: [Placement] = []
  /// Each track's window size: the size it has where it is in view, so a window keeps one size
  /// for the whole scroll (half columns differ by a point between the two halves of the view).
  private var sizes: [CGSize] = []

  /// `before` and `after` are the workspace's `arrangement` before and after its view moved.
  /// Each window slides from one frame to the other, kept where macOS accepts a position, so a
  /// window leaving or entering on the left waits at the edge instead of going further.
  public init(from before: [Placement], to after: [Placement], on display: DisplayInfo) {
    let area = display.visibleFrame
    let old = Dictionary(before.map { ($0.id, $0.frame) }, uniquingKeysWith: { first, _ in first })
    for placement in after {
      guard let previous = old[placement.id] else { continue }
      let target = placement.frame
      let wasShown = area.shows(previous)
      let isShown = area.shows(target)
      guard wasShown || isShown else { continue }
      let track = Track(
        id: placement.id, start: previous.origin, end: target.origin,
        allowedX: Parking.allowedX(width: target.width, on: display))
      tracks.append(track)
      if !wasShown {
        // Coming in from the right, this is where the window is parked already.
        start.append(
          Placement(
            id: placement.id, frame: CGRect(origin: track.position(at: 0), size: target.size)))
      }
      sizes.append(isShown ? target.size : previous.size)
      finals.append(
        isShown
          ? placement
          : Placement(id: placement.id, frame: Parking.frame(for: previous, on: display)))
      returns.append(
        Placement(
          id: placement.id, frame: wasShown ? previous : Parking.frame(for: previous, on: display)))
    }
  }

  /// The windows taking part.
  public var windows: Set<WindowID> {
    Set(tracks.map(\.id))
  }

  /// Where the windows taking part are `progress` of the way along, following the fingers
  /// exactly, at the size they have in view.
  public func placements(at progress: Double) -> [Placement] {
    zip(tracks, sizes).map { track, size in
      Placement(
        id: track.id,
        frame: CGRect(origin: track.position(at: progress, easing: Easing.linear), size: size))
    }
  }
}
