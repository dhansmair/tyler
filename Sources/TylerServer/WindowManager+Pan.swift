import CoreGraphics
import TylerCore

/// How the windows move when another workspace comes into view: worked out up front, so a slide
/// or a pan can run it forwards, part-way, or back.
struct SlidePlan {
  let target: Int
  let direction: ScrollDirection
  /// Where the incoming windows wait before they slide in: resized to their slots, off screen.
  var start: [Placement] = []
  var tracks: [Track] = []
  /// Where every window ends up once the target workspace is on screen.
  var finals: [Placement] = []
  /// Where every window goes back to if the target doesn't come into view after all: the current
  /// windows to where they were, the incoming ones to their parked frames.
  var returns: [Placement] = []
}

/// What a trackpad pan moves. Only the row of workspaces for now; the strip layout will add a
/// case for scrolling its columns, sharing the pan, the snapping and the pacing below.
enum PanTarget {
  /// The neighbouring workspaces, both worked out when the pan began (frames read later would be
  /// mid-slide). With two workspaces both sides bring in the same one, from opposite edges.
  case workspaceRow(prev: SlidePlan, next: SlidePlan)
}

/// A trackpad pan in progress.
struct PanSession {
  let target: PanTarget
  /// How far the content has moved, in display widths: -1 has the next workspace fully in view,
  /// 1 the previous one. Fingers moving left move the content left, towards the next workspace.
  var offset: Double = 0
  /// The side whose incoming windows are out of their parked spots.
  var shownSide: ScrollDirection?
  /// Whether `offset` has been applied to the windows yet.
  var isPlaced = true
  /// Places the windows at most once a frame.
  var throttle = Throttle()
}

extension WindowManager {
  /// The release speed, in display widths per second, from which a pan goes on to the workspace
  /// it was heading for even if it is less than halfway there.
  static let flickVelocity = 1.0
  /// The least share of a whole slide's duration that going back takes: even from close to the
  /// start, the windows settle visibly rather than snap.
  static let returnShare = 0.6

  /// Lets a trackpad pan slide between workspaces: the windows follow the fingers, and on release
  /// the row settles on the neighbouring workspace or back on the current one (see `Snap`).
  func apply(_ update: PanUpdate) {
    switch update {
    case .began: beginPan()
    case .moved(let offset): movePan(to: offset)
    case .ended(let velocity): endPan(velocity: velocity)
    }
  }

  /// The windows a pan in progress may move.
  var panningWindows: Set<WindowID> {
    guard case .workspaceRow(let prev, let next) = pan?.target else { return [] }
    return Set((prev.tracks + next.tracks).map(\.id))
  }

  private func beginPan() {
    finishAnimation()
    guard config.gestures.swipe, state == .running, tilingEnabled, drag == nil,
      workspaces.count > 1, let display = displays.displays.first,
      let prev = workspaces.index(of: .prev), let next = workspaces.index(of: .next)
    else { return }
    syncWorkspaces()
    pan = PanSession(
      target: .workspaceRow(
        prev: slidePlan(to: prev, direction: .prev, on: display),
        next: slidePlan(to: next, direction: .next, on: display)))
  }

  /// Takes the fingers' travel, in trackpad widths, and moves the windows with it. Moving every
  /// window is a round trip to its app each, and pans report faster than slow apps move, so the
  /// windows are placed at most once a frame: offsets arriving in between replace each other.
  private func movePan(to travel: Double) {
    guard pan != nil else { return }
    pan?.offset = min(1, max(-1, travel / config.gestures.swipeDistance))
    pan?.isPlaced = false
    if pan?.throttle.isHolding == false { placePan() }
  }

  /// Places the windows for the newest offset, then holds further steps back for a frame.
  private func placePan() {
    guard let session = pan, !session.isPlaced else {
      pan?.throttle.release()
      return
    }
    pan?.isPlaced = true
    let side = Self.side(of: session.offset)
    show(side, of: session)
    if let side {
      let plan = Self.plan(for: side, in: session.target)
      let progress = abs(session.offset)
      for track in plan.tracks {
        nudge(track.id, to: track.position(at: progress, easing: Easing.linear))
      }
    }
    pan?.throttle.hold(for: animator.frameInterval, on: clock) { [weak self] in
      self?.placePan()
    }
  }

  /// The fingers lifted: the row settles where `Snap` says, sliding on from where it is.
  private func endPan(velocity: Double) {
    guard let session = pan else { return }
    forgetPan()
    let distance = config.gestures.swipeDistance
    let point = Snap.target(
      offset: session.offset, velocity: velocity / distance, points: [-1, 0, 1],
      flickVelocity: Self.flickVelocity)
    // A flick may head for a side whose windows haven't come out yet.
    let side = Self.side(of: point) ?? session.shownSide
    show(side, of: session)
    guard let side else { return }
    let plan = Self.plan(for: side, in: session.target)
    let progress = Self.side(of: session.offset) == side ? abs(session.offset) : 0
    if point == 0 {
      animate(
        start: [], tracks: plan.tracks, finals: plan.returns, from: progress, to: 0,
        minimumDuration: animator.duration * Self.returnShare)
      return
    }
    workspaces.select(plan.target)
    animate(start: [], tracks: plan.tracks, finals: plan.finals, from: progress, to: 1)
    focusCurrentWorkspace()
  }

  /// Gets the incoming windows of `side` ready to slide in, after putting back those of the side
  /// shown so far, if that was another.
  private func show(_ side: ScrollDirection?, of session: PanSession) {
    guard side != session.shownSide else { return }
    if let shown = session.shownSide {
      place(Self.plan(for: shown, in: session.target).returns)
    }
    if let side {
      place(Self.plan(for: side, in: session.target).start)
    }
    pan?.shownSide = side
  }

  /// Ends a pan early, every window back where it was when the pan began.
  func abandonPan() {
    guard let session = pan else { return }
    forgetPan()
    if let shown = session.shownSide {
      place(Self.plan(for: shown, in: session.target).returns)
    }
  }

  /// Forgets the pan, and any step of it still waiting, leaving the windows where they are.
  func forgetPan() {
    pan?.throttle.release()
    pan = nil
  }

  /// Which neighbour an offset brings into view: content moving left (negative) shows the next.
  private static func side(of offset: Double) -> ScrollDirection? {
    offset < 0 ? .next : offset > 0 ? .prev : nil
  }

  private static func plan(for side: ScrollDirection, in target: PanTarget) -> SlidePlan {
    switch target {
    case .workspaceRow(let prev, let next): side == .next ? next : prev
    }
  }
}
