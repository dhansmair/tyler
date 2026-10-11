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
  ///
  /// Nothing slides onto another display: a window whose way out or in passes through a side
  /// with a neighbour jumps instead. A leaving one goes straight to its parking spot, an
  /// entering one straight into its slot (both in `start`, with no track).
  public init(
    to target: Int, direction: ScrollDirection, leaving: [Placement], entering: [Placement],
    on display: DisplayInfo
  ) {
    self.target = target
    let leavesByJumping = display.neighbours.contains(direction.outgoingSide)
    let entersByJumping = display.neighbours.contains(direction.opposite.outgoingSide)
    for window in leaving {
      let parked = Placement(id: window.id, frame: Parking.frame(for: window.frame, on: display))
      if leavesByJumping {
        start.append(parked)
      } else {
        tracks.append(.leaving(window.id, from: window.frame, direction: direction, on: display))
      }
      finals.append(parked)
      returns.append(window)
    }
    for slot in entering {
      if entersByJumping {
        start.append(slot)
      } else {
        let track = Track.entering(slot.id, into: slot.frame, direction: direction, on: display)
        // Coming in from the parking edge, this is where the window is parked already.
        start.append(
          Placement(
            id: slot.id, frame: CGRect(origin: track.position(at: 0), size: slot.frame.size)))
        tracks.append(track)
      }
      finals.append(slot)
      returns.append(Placement(id: slot.id, frame: Parking.frame(for: slot.frame, on: display)))
    }
  }

  /// The windows taking part, sliding or jumping.
  public var windows: Set<WindowID> {
    Set(finals.map(\.id))
  }
}
