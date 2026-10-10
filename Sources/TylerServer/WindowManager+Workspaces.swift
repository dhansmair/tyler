import CoreGraphics
import TylerCore

/// Workspaces: switching between them with a slide, sending windows to another one, and
/// putting windows back where they came from.
extension WindowManager {
  /// A slide in progress. `finals` is where every window involved must end up, whether the slide
  /// runs to the end or is cut short.
  struct RunningAnimation {
    let id: Int
    let task: Task<Void, Never>
    let finals: [Placement]
  }

  // MARK: - Commands

  func handleWorkspaceRequest(_ request: Request) -> Response {
    switch request {
    case .workspace(let target): switchWorkspace(target)
    case .moveToWorkspace(let target, let follow): moveToWorkspace(target, follow: follow)
    case .ping, .status, .list, .reload, .tiling, .retile, .focus, .swap, .layout, .ratio,
      .toggleFloat:
      .error("not a workspace request")
    }
  }

  /// Makes another workspace current: its windows slide in while the current ones slide out and
  /// park, then focus goes to the target's focused window (none if it is empty).
  public func switchWorkspace(_ target: WorkspaceTarget) -> Response {
    if let failure = beginCommand() { return failure }
    guard let index = workspaces.index(of: target) else { return outOfRange(target) }
    guard index != workspaces.currentIndex else { return .message("workspace \(index + 1)") }
    let failures = show(
      index, direction: direction(of: target, from: workspaces.currentIndex, to: index),
      focusing: true)
    return failures == 0 ? .message("workspace \(index + 1)") : outcome(failures: failures)
  }

  /// Sends the focused tiled window to another workspace, where it becomes that workspace's focused
  /// window. Without `follow` it slides off and parks, and focus stays on this workspace; with
  /// `follow` the view switches along with it.
  public func moveToWorkspace(_ target: WorkspaceTarget, follow: Bool) -> Response {
    if let failure = beginCommand() { return failure }
    guard let windowID = registry.focusedID, let source = workspaces.index(containing: windowID)
    else {
      return .error("the focused window is not tiled")
    }
    guard let index = workspaces.index(of: target) else { return outOfRange(target) }
    guard index != source else { return .message("already on workspace \(index + 1)") }

    let current = workspaces.currentIndex
    let direction = direction(of: target, from: source, to: index)
    workspaces.move(windowID, to: index)
    var failures = 0
    if follow && index != current {
      failures += show(index, direction: direction, focusing: true)
    } else {
      if source == current { failures += slideOut(windowID, towards: direction) }
      failures += applyLayout()
      if source == current { focusCurrentWorkspace() }
    }
    return failures == 0 ? .message("moved to workspace \(index + 1)") : outcome(failures: failures)
  }

  // MARK: - Switching

  /// The OS focused `windowID` (a click, cmd-tab, an app raising itself). If it lives on a
  /// parked workspace and the focus wasn't tylerd's own doing, that workspace comes into view.
  func focusChanged(to windowID: WindowID) {
    let isEcho = bookkeeping.pendingFocus.remove(windowID) != nil
    workspaces.setFocus(windowID)
    guard !isEcho, state == .running, tilingEnabled,
      let index = workspaces.index(containing: windowID), index != workspaces.currentIndex
    else { return }
    show(index, direction: index > workspaces.currentIndex ? .next : .prev, focusing: false)
  }

  /// Makes the workspace at `index` current. The current windows slide out sideways by the
  /// width of the visible frame and park; the target's windows slide in from the other side.
  /// Returns how many windows could not be placed up front.
  @discardableResult
  func show(_ index: Int, direction: ScrollDirection, focusing: Bool) -> Int {
    finishAnimation()
    endDrag()
    // Sync before switching, never after: the target's windows are parked, and a parked frame
    // can overlap a neighbouring display more than this one, which would drop them.
    syncWorkspaces()
    guard let display = displays.displays.first else {
      workspaces.select(index)
      return 0
    }
    let plan = slidePlan(to: index, direction: direction, on: display)
    workspaces.select(index)
    let failures = animate(start: plan.start, tracks: plan.tracks, finals: plan.finals)
    if focusing { focusCurrentWorkspace() }
    return failures
  }

  /// How the windows move when the workspace at `index` comes into view from `direction`: the
  /// current workspace's windows leave, the target's come in. Reads the current frames, so it
  /// must be worked out before any of these windows moves.
  func slidePlan(
    to index: Int, direction: ScrollDirection, on display: DisplayInfo
  ) -> SlidePlan {
    var plan = SlidePlan(target: index, direction: direction)
    for windowID in workspaces.current.windows {
      guard let frame = registry.window(withID: windowID)?.frame else { continue }
      plan.tracks.append(.leaving(windowID, from: frame, direction: direction, on: display))
      plan.finals.append(Placement(id: windowID, frame: Parking.frame(for: frame, on: display)))
      plan.returns.append(Placement(id: windowID, frame: frame))
    }
    for placement in workspaces[index].placements(in: display.visibleFrame) {
      let track = Track.entering(
        placement.id, into: placement.frame, direction: direction, on: display)
      // Coming in from the right, this is where the window is parked already.
      plan.start.append(
        Placement(
          id: placement.id, frame: CGRect(origin: track.position(at: 0), size: placement.frame.size)
        ))
      plan.tracks.append(track)
      plan.finals.append(placement)
      plan.returns.append(
        Placement(id: placement.id, frame: Parking.frame(for: placement.frame, on: display)))
    }
    return plan
  }

  /// Slides one visible window off the display towards the workspace it was sent to, and parks
  /// it. The view stays put, so the window moves the opposite way to windows leaving when the
  /// view scrolls: one sent to the `next` workspace goes right, where that workspace comes from.
  private func slideOut(_ windowID: WindowID, towards direction: ScrollDirection) -> Int {
    guard let display = displays.displays.first,
      let frame = registry.window(withID: windowID)?.frame
    else { return 0 }
    return animate(
      start: [],
      tracks: [.leaving(windowID, from: frame, direction: direction.opposite, on: display)],
      finals: [Placement(id: windowID, frame: Parking.frame(for: frame, on: display))])
  }

  func focusCurrentWorkspace() {
    guard let target = workspaces.current.focused ?? workspaces.current.windows.first else {
      unfocusParkedWindow()
      return
    }
    do {
      try requestFocus(target)
    } catch {
      Self.log.error("cannot focus window \(target.rawValue): \(error.description)")
    }
  }

  /// An empty workspace has nothing to focus, but the window that had focus is parked now and
  /// would still get every key typed. A floated window stays on screen, so it keeps focus.
  private func unfocusParkedWindow() {
    guard let focusedID = registry.focusedID, workspaces.index(containing: focusedID) != nil
    else { return }
    do {
      try backend.unfocus()
    } catch {
      Self.log.error("cannot take focus from window \(focusedID.rawValue): \(error.description)")
    }
  }

  private func direction(
    of target: WorkspaceTarget, from source: Int, to index: Int
  ) -> ScrollDirection {
    switch target {
    case .prev: .prev
    case .next: .next
    case .number: index > source ? .next : .prev
    }
  }

  private func outOfRange(_ target: WorkspaceTarget) -> Response {
    guard case .number(let number) = target else { return .error("no such workspace") }
    return .error("workspace \(number) does not exist (use 1 to \(workspaces.count))")
  }

  // MARK: - Animation

  /// Windows that are sliding right now (or about to be placed at the end of a slide), or that
  /// a trackpad pan may move.
  var animatingWindows: Set<WindowID> {
    Set(animation?.finals.map(\.id) ?? []).union(panningWindows)
  }

  /// Puts windows at `start`, slides them along `tracks`, and finally places them at `finals`
  /// with a full resize. With a snapping animator (or nothing to slide) the windows go straight
  /// to `finals`. Returns how many windows could not be placed synchronously; failures during
  /// the slide are logged. A slide that takes over from a released swipe runs only part of the
  /// tracks, `from` one progress `to` another, easing out, taking at least `minimumDuration`.
  @discardableResult
  func animate(
    start: [Placement], tracks: [Track], finals: [Placement], from: Double = 0, to end: Double = 1,
    minimumDuration: Duration = .zero
  ) -> Int {
    finishAnimation()
    guard animator.stepCount > 0, !tracks.isEmpty else { return place(finals) }
    let failures = place(start)
    animationCount += 1
    let id = animationCount
    let animator = animator
    let task = Task { [weak self] in
      let move: (WindowID, CGPoint) -> Void = { windowID, origin in
        self?.nudge(windowID, to: origin)
      }
      let isComplete =
        from == 0 && end == 1
        ? await animator.run(tracks, move: move)
        : await animator.run(
          tracks, from: from, to: end, minimumDuration: minimumDuration, move: move)
      if isComplete { self?.completeAnimation(id) }
    }
    animation = RunningAnimation(id: id, task: task, finals: finals)
    return failures
  }

  /// Ends a slide early: the windows jump to where the slide would have left them. A trackpad
  /// pan in progress is abandoned, its windows back where they started.
  func finishAnimation() {
    abandonPan()
    guard let running = animation else { return }
    animation = nil
    running.task.cancel()
    place(running.finals)
  }

  /// Stops a slide (or a pan) and leaves the windows wherever they are.
  func cancelAnimation() {
    forgetPan()
    animation?.task.cancel()
    animation = nil
  }

  private func completeAnimation(_ id: Int) {
    guard let running = animation, running.id == id else { return }
    animation = nil
    place(running.finals)
  }

  func nudge(_ windowID: WindowID, to origin: CGPoint) {
    rememberOriginalFrame(of: windowID)
    do {
      try backend.setPosition(origin, of: windowID)
    } catch {
      // One missed frame is invisible; the final placement reports real failures.
      Self.log.debug("cannot slide window \(windowID.rawValue): \(error.description)")
    }
  }

  // MARK: - Restoring

  /// Brings every parked window back to where it was before tylerd moved it and empties the
  /// other workspaces. The current workspace keeps its list (so `tiling on` restores its order) and
  /// its windows stay where they are.
  func unparkAll() {
    for index in workspaces.indices where index != workspaces.currentIndex {
      restoreOriginalFrames(of: workspaces[index].windows)
      workspaces[index].sync(eligible: [])
    }
  }

  /// Moves windows back to their original frames. Windows tylerd never moved are skipped.
  /// Failures are logged and don't stop the others.
  @discardableResult
  func restoreOriginalFrames(of windowIDs: [WindowID]) -> Int {
    var failures = 0
    for windowID in windowIDs {
      guard let frame = bookkeeping.originalFrames[windowID] else { continue }
      do {
        try backend.setFrame(frame, of: windowID)
      } catch {
        failures += 1
        Self.log.error("cannot restore window \(windowID.rawValue): \(error.description)")
      }
    }
    return failures
  }
}
