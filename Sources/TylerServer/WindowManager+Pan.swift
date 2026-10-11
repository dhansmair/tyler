import CoreGraphics
import TylerCore

/// What a trackpad pan moves: the row of workspaces, or the columns of a strip workspace. Both
/// share the pan, the snapping and the pacing below.
enum PanTarget {
  /// The neighbouring workspaces, both worked out when the pan began (frames read later would be
  /// mid-slide). With two workspaces both sides bring in the same one, from opposite edges.
  case workspaceRow(prev: SlidePlan, next: SlidePlan)
  /// The current workspace's strip, with every view it can rest at.
  case strip(StripScroll)
}

/// A trackpad pan in progress.
struct PanSession {
  let target: PanTarget
  /// How far the content has moved, in display widths: -1 has the next workspace fully in view,
  /// 1 the previous one. Fingers moving left move the content left, towards the next workspace
  /// (or the strip's later columns, where it isn't limited to one width).
  var offset: Double = 0
  /// The side whose incoming windows are out of their parked spots.
  var shownSide: ScrollDirection?
  /// The pair of strip views whose windows are out of their parked spots, and their scroll.
  var shownSegment: (index: Int, plan: ScrollPlan)?
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

  /// Lets a trackpad pan slide between workspaces, or along the current workspace's strip: the
  /// windows follow the fingers, and on release they settle on a neighbouring workspace or view,
  /// or back where they began (see `Snap`).
  func apply(_ update: PanUpdate) {
    switch update {
    case .began: beginPan()
    case .moved(let offset): movePan(to: offset)
    case .ended(let velocity): endPan(velocity: velocity)
    }
  }

  /// The windows a pan in progress may move.
  var panningWindows: Set<WindowID> {
    switch pan?.target {
    case .workspaceRow(let prev, let next): Set((prev.tracks + next.tracks).map(\.id))
    case .strip(let scroll): Set(scroll.views[0].arrangement.map(\.id))
    case nil: []
    }
  }

  /// Begins a pan. On a strip workspace it scrolls the strip and never switches workspaces.
  private func beginPan() {
    finishAnimation()
    guard config.gestures.swipe, isTiling, interaction.isIdle, let display = focusedDisplay
    else { return }
    if workspaces.current.layout == .strip {
      beginStripPan(on: display)
      return
    }
    guard workspaces.count > 1,
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
    guard let session = pan else { return }
    let offset = travel / config.gestures.swipeDistance
    if case .strip = session.target {
      pan?.offset = offset
    } else {
      pan?.offset = min(1, max(-1, offset))
    }
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
    switch session.target {
    case .workspaceRow(let prev, let next):
      let side = ScrollDirection(revealedBy: session.offset)
      show(side, of: session, prev: prev, next: next)
      if let side {
        let plan = side == .next ? next : prev
        let progress = abs(session.offset)
        for track in plan.tracks {
          nudge(track.id, to: track.position(at: progress, easing: Easing.linear))
        }
      }
    case .strip(let scroll):
      placeStrip(scroll, movedBy: session.offset)
    }
    pan?.throttle.hold(for: animator.frameInterval, on: clock) { [weak self] in
      self?.placePan()
    }
  }

  /// The fingers lifted: the row settles where `Snap` says, sliding on from where it is.
  private func endPan(velocity: Double) {
    guard let session = pan else { return }
    forgetPan()
    let prev: SlidePlan
    let next: SlidePlan
    switch session.target {
    case .workspaceRow(let prevPlan, let nextPlan):
      (prev, next) = (prevPlan, nextPlan)
    case .strip(let scroll):
      endStripPan(scroll, session: session, velocity: velocity)
      return
    }
    let distance = config.gestures.swipeDistance
    let point = Snap.target(
      offset: session.offset, velocity: velocity / distance, points: [-1, 0, 1],
      flickVelocity: Self.flickVelocity)
    // A flick may head for a side whose windows haven't come out yet.
    let side = ScrollDirection(revealedBy: point) ?? session.shownSide
    show(side, of: session, prev: prev, next: next)
    guard let side else { return }
    let plan = side == .next ? next : prev
    let progress = ScrollDirection(revealedBy: session.offset) == side ? abs(session.offset) : 0
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
  private func show(
    _ side: ScrollDirection?, of session: PanSession, prev: SlidePlan, next: SlidePlan
  ) {
    guard side != session.shownSide else { return }
    if let shown = session.shownSide {
      place((shown == .next ? next : prev).returns)
    }
    if let side {
      place((side == .next ? next : prev).start)
    }
    pan?.shownSide = side
  }

  /// Ends a pan early, every window back where it was when the pan began.
  func abandonPan() {
    guard let session = pan else { return }
    forgetPan()
    switch session.target {
    case .workspaceRow(let prev, let next):
      if let shown = session.shownSide {
        place((shown == .next ? next : prev).returns)
      }
    case .strip(let scroll):
      if let shown = session.shownSegment {
        place(scroll.resting(shown.plan.windows, at: scroll.startIndex))
      }
    }
  }

  /// Forgets the pan, and any step of it still waiting, leaving the windows where they are.
  func forgetPan() {
    pan?.throttle.release()
    pan = nil
  }

}
