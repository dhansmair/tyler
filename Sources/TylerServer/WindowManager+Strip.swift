import CoreGraphics
import TylerCore

/// The strip layout: window sizes, and scrolling its view.
extension WindowManager {
  /// Sets the focused window's size in the strip layout (`quarter` pairs it with a neighbour, see
  /// `Workspace.setSizeWithPartner`). Other layouts keep it for when the workspace turns to the
  /// strip.
  public func setSize(_ choice: SizeChoice) -> Response {
    if let failure = beginCommand() { return failure }
    guard let windowID = registry.focusedID, workspaces.current.contains(windowID) else {
      return .error("the focused window is not tiled")
    }
    let size: WindowSize
    switch choice {
    case .set(let chosen): size = chosen
    case .next: size = workspaces.current.size(of: windowID).next
    }
    let snapshot = stripSnapshot()
    if workspaces.current.setSizeWithPartner(size, of: windowID) == .noPartner {
      return .error(
        "a quarter window shares its column with the next or previous window, and neither is free")
    }
    let failures = scrollIfViewMoved(since: snapshot) ?? applyLayout()
    guard failures == 0 else { return outcome(failures: failures) }
    return .message(
      workspaces.current.layout == .strip
        ? "size \(size.rawValue)" : "size \(size.rawValue) (used by the strip layout)")
  }

  /// The current workspace before a change: its strip's view and every window's frame with it,
  /// so the change can be animated as a scroll. `nil` without a display.
  struct StripSnapshot {
    let display: DisplayInfo
    let view: WindowID?
    let arrangement: [Placement]
  }

  func stripSnapshot() -> StripSnapshot? {
    focusedDisplay.map { display in
      StripSnapshot(
        display: display, view: workspaces.current.firstVisible,
        arrangement: workspaces.current.arrangement(in: display.visibleFrame, gaps: gaps))
    }
  }

  /// Scrolls the strip from `snapshot` to the current workspace's view, if a change moved it.
  /// Returns how many windows could not be placed up front, or `nil` if the view didn't move
  /// (or the workspace isn't a strip) and nothing was done.
  func scrollIfViewMoved(since snapshot: StripSnapshot?) -> Int? {
    guard let snapshot, workspaces.current.layout == .strip,
      workspaces.current.firstVisible != snapshot.view
    else { return nil }
    let plan = ScrollPlan(
      from: snapshot.arrangement,
      to: workspaces.current.arrangement(in: snapshot.display.visibleFrame, gaps: gaps),
      on: snapshot.display)
    return animate(start: plan.start, tracks: plan.tracks, finals: plan.finals)
  }

  // MARK: - Swiping along the strip

  /// Begins a pan along the current workspace's strip, if it has anywhere to scroll to.
  func beginStripPan(on display: DisplayInfo) {
    syncWorkspaces()
    guard
      let scroll = StripScroll(
        views: workspaces.current.stripViews(in: display.visibleFrame, gaps: gaps),
        current: workspaces.current.firstVisible, on: display)
    else { return }
    pan = PanSession(target: .strip(scroll))
  }

  /// Moves the strip's windows with the fingers: the scroll between the two views the position
  /// lies between, run part-way.
  func placeStrip(_ scroll: StripScroll, movedBy offset: Double) {
    let position = scroll.position(movedBy: offset)
    // Still on the view the pan began at (as at the strip's ends): nothing to bring out yet.
    if pan?.shownSegment == nil, position == scroll.offsets[scroll.startIndex] { return }
    let (index, progress) = scroll.segment(at: position)
    guard let shown = pan?.shownSegment, shown.index == index else {
      let plan = showSegment(index, of: scroll, at: progress, after: pan?.shownSegment?.plan)
      pan?.shownSegment = (index, plan)
      return
    }
    for track in shown.plan.tracks {
      nudge(track.id, to: track.position(at: progress, easing: Easing.linear))
    }
  }

  /// Brings out the windows of the scroll between views `index` and `index + 1`, `progress` of
  /// the way along, after parking those of the scroll shown so far that take no part. Returns
  /// the new scroll.
  private func showSegment(
    _ index: Int, of scroll: StripScroll, at progress: Double, after shown: ScrollPlan?
  ) -> ScrollPlan {
    let plan = scroll.plan(forSegment: index)
    if let shown {
      // Out of view at both ends of the new pair, so parked at either.
      place(scroll.resting(shown.windows.subtracting(plan.windows), at: index))
    }
    place(plan.placements(at: progress))
    return plan
  }

  /// The fingers lifted: the strip settles on the view `Snap` picks, sliding on from where it is,
  /// and focus moves into the view if the focused window left it.
  func endStripPan(_ scroll: StripScroll, session: PanSession, velocity: Double) {
    let distance = config.gestures.swipeDistance
    let width = Double(scroll.viewWidth)
    let position = scroll.position(movedBy: session.offset)
    let target = Snap.target(
      offset: position, velocity: CGFloat(-velocity / distance * width), points: scroll.offsets,
      flickVelocity: CGFloat(Self.flickVelocity * width))
    guard let targetIndex = scroll.offsets.firstIndex(of: target),
      session.shownSegment != nil || targetIndex != scroll.startIndex
    else { return }  // nothing moved, and nothing will
    var (index, progress) = scroll.segment(at: position)
    // Resting exactly on a view, a flick may head away from the pair the position counts for.
    if targetIndex < index {
      (index, progress) = (targetIndex, 1)
    } else if targetIndex > index + 1 {
      (index, progress) = (targetIndex - 1, 0)
    }
    let shown = session.shownSegment.flatMap { $0.index == index ? $0.plan : nil }
    let plan =
      shown ?? showSegment(index, of: scroll, at: progress, after: session.shownSegment?.plan)
    let isForward = targetIndex == index + 1
    let focusMoved = workspaces.current.scroll(
      toFirstVisible: scroll.views[targetIndex].firstVisible)
    animate(
      start: [], tracks: plan.tracks, finals: isForward ? plan.finals : plan.returns,
      from: progress, to: isForward ? 1 : 0,
      minimumDuration: targetIndex == scroll.startIndex
        ? animator.duration * Self.returnShare : .zero)
    if focusMoved { focusCurrentWorkspace() }
  }
}
