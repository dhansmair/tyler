import CoreGraphics

/// How the windows move when another workspace comes into view: worked out up front, so a slide
/// or a trackpad pan can run it forwards, part-way, or back.
public struct SlidePlan: Equatable, Sendable {
  /// The index of the workspace coming into view.
  public let target: Int
  /// Where the incoming windows wait before they slide in: resized to their slots, off screen.
  public private(set) var start: [Placement] = []
  public private(set) var tracks: [Track] = []
  /// Where every window ends up once the target workspace is on screen.
  public private(set) var finals: [Placement] = []
  /// Where every window goes back to if the target doesn't come into view after all: the current
  /// windows to where they were, the incoming ones to their parked frames.
  public private(set) var returns: [Placement] = []

  /// The windows on screen now (`leaving`, with their current frames) slide out towards
  /// `direction` and park; the target's windows (`entering`, in their slots) come in from the
  /// other side. The leaving frames must be read before any of these windows moves.
  public init(
    to target: Int, direction: ScrollDirection, leaving: [Placement], entering: [Placement],
    on display: DisplayInfo
  ) {
    self.target = target
    for window in leaving {
      tracks.append(.leaving(window.id, from: window.frame, direction: direction, on: display))
      finals.append(Placement(id: window.id, frame: Parking.frame(for: window.frame, on: display)))
      returns.append(window)
    }
    for slot in entering {
      let track = Track.entering(slot.id, into: slot.frame, direction: direction, on: display)
      // Coming in from the right, this is where the window is parked already.
      start.append(
        Placement(id: slot.id, frame: CGRect(origin: track.position(at: 0), size: slot.frame.size)))
      tracks.append(track)
      finals.append(slot)
      returns.append(Placement(id: slot.id, frame: Parking.frame(for: slot.frame, on: display)))
    }
  }
}
