import CoreGraphics
import MWMCore

/// Virtual monitors: switching between them with a slide, sending windows to another one, and
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

  func handleMonitorRequest(_ request: Request) -> Response {
    switch request {
    case .monitor(let target): switchMonitor(target)
    case .moveToMonitor(let target, let follow): moveToMonitor(target, follow: follow)
    default: .error("not a monitor request")
    }
  }

  /// Makes another monitor current: its windows slide in while the current ones slide out and
  /// park, then focus goes to the target's focused window (none if it is empty).
  public func switchMonitor(_ target: MonitorTarget) -> Response {
    if let failure = beginCommand() { return failure }
    guard let index = monitors.index(of: target) else { return outOfRange(target) }
    guard index != monitors.currentIndex else { return .message("monitor \(index + 1)") }
    let failures = show(
      index, direction: direction(of: target, from: monitors.currentIndex, to: index),
      focusing: true)
    return failures == 0 ? .message("monitor \(index + 1)") : outcome(failures: failures)
  }

  /// Sends the focused tiled window to another monitor, where it becomes that monitor's focused
  /// window. Without `follow` it slides off and parks, and focus stays on this monitor; with
  /// `follow` the view switches along with it.
  public func moveToMonitor(_ target: MonitorTarget, follow: Bool) -> Response {
    if let failure = beginCommand() { return failure }
    guard let windowID = registry.focusedID, let source = monitors.monitor(of: windowID) else {
      return .error("the focused window is not tiled")
    }
    guard let index = monitors.index(of: target) else { return outOfRange(target) }
    guard index != source else { return .message("already on monitor \(index + 1)") }

    let current = monitors.currentIndex
    let direction = direction(of: target, from: source, to: index)
    monitors.move(windowID, to: index)
    var failures = 0
    if follow && index != current {
      failures += show(index, direction: direction, focusing: true)
    } else {
      if source == current { failures += slideOut(windowID, direction: direction) }
      failures += applyLayout()
      if source == current { focusCurrentMonitor() }
    }
    return failures == 0 ? .message("moved to monitor \(index + 1)") : outcome(failures: failures)
  }

  // MARK: - Switching

  /// The OS focused `windowID` (a click, cmd-tab, an app raising itself). If it lives on a
  /// parked monitor and the focus wasn't mwmd's own doing, that monitor comes into view.
  func focusChanged(to windowID: WindowID) {
    let isEcho = pendingFocus.remove(windowID) != nil
    monitors.setFocus(windowID)
    guard !isEcho, state == .running, tilingEnabled,
      let index = monitors.monitor(of: windowID), index != monitors.currentIndex
    else { return }
    show(index, direction: index > monitors.currentIndex ? .down : .up, focusing: false)
  }

  /// Makes the monitor at `index` current. The current windows slide out by a display height
  /// and park; the target's windows are put a display height away and slide into their slots.
  /// Returns how many windows could not be placed up front.
  @discardableResult
  func show(_ index: Int, direction: ScrollDirection, focusing: Bool) -> Int {
    finishAnimation()
    // Sync before switching, never after: the target's windows are parked, and a parked frame
    // can overlap a neighbouring display more than this one, which would drop them.
    syncMonitors()
    let outgoing = monitors.current.windows
    monitors.select(index)
    guard let display = displays.displays.first else { return 0 }

    let offset = direction.outgoingOffset(height: display.frame.height)
    var tracks: [Track] = []
    var start: [Placement] = []
    var finals: [Placement] = []
    for windowID in outgoing {
      guard let frame = registry.window(withID: windowID)?.frame else { continue }
      tracks.append(
        Track(id: windowID, start: frame.origin, end: frame.offsetBy(dx: 0, dy: offset).origin))
      finals.append(Placement(id: windowID, frame: Parking.frame(for: frame.size, on: display)))
    }
    for placement in monitors.current.placements(in: display.visibleFrame) {
      let from = placement.frame.offsetBy(dx: 0, dy: -offset)
      start.append(Placement(id: placement.id, frame: from))
      tracks.append(Track(id: placement.id, start: from.origin, end: placement.frame.origin))
      finals.append(placement)
    }
    let failures = animate(start: start, tracks: tracks, finals: finals)
    if focusing { focusCurrentMonitor() }
    return failures
  }

  /// Slides one visible window off the display and parks it.
  private func slideOut(_ windowID: WindowID, direction: ScrollDirection) -> Int {
    guard let display = displays.displays.first,
      let frame = registry.window(withID: windowID)?.frame
    else { return 0 }
    let offset = direction.outgoingOffset(height: display.frame.height)
    return animate(
      start: [],
      tracks: [
        Track(id: windowID, start: frame.origin, end: frame.offsetBy(dx: 0, dy: offset).origin)
      ],
      finals: [Placement(id: windowID, frame: Parking.frame(for: frame.size, on: display))])
  }

  private func focusCurrentMonitor() {
    guard let target = monitors.current.focused ?? monitors.current.windows.first else { return }
    do {
      try requestFocus(target)
    } catch {
      Self.log.error("cannot focus window \(target.rawValue): \(error.description)")
    }
  }

  private func direction(
    of target: MonitorTarget, from source: Int, to index: Int
  ) -> ScrollDirection {
    switch target {
    case .up: .up
    case .down: .down
    case .number: index > source ? .down : .up
    }
  }

  private func outOfRange(_ target: MonitorTarget) -> Response {
    guard case .number(let number) = target else { return .error("no such monitor") }
    return .error("monitor \(number) does not exist (use 1 to \(monitors.count))")
  }

  // MARK: - Animation

  /// Windows that are sliding right now (or about to be placed at the end of a slide).
  var animatingWindows: Set<WindowID> {
    Set(animation?.finals.map(\.id) ?? [])
  }

  /// Puts windows at `start`, slides them along `tracks`, and finally places them at `finals`
  /// with a full resize. With a snapping animator (or nothing to slide) the windows go straight
  /// to `finals`. Returns how many windows could not be placed synchronously; failures during
  /// the slide are logged.
  private func animate(start: [Placement], tracks: [Track], finals: [Placement]) -> Int {
    finishAnimation()
    guard animator.stepCount > 0, !tracks.isEmpty else { return place(finals) }
    let failures = place(start)
    animationCount += 1
    let id = animationCount
    let animator = animator
    let task = Task { [weak self] in
      let isComplete = await animator.run(tracks) { windowID, origin in
        self?.nudge(windowID, to: origin)
      }
      if isComplete { self?.completeAnimation(id) }
    }
    animation = RunningAnimation(id: id, task: task, finals: finals)
    return failures
  }

  /// Ends a slide early: the windows jump to where the slide would have left them.
  func finishAnimation() {
    guard let running = animation else { return }
    animation = nil
    running.task.cancel()
    place(running.finals)
  }

  /// Stops a slide and leaves the windows wherever they are.
  func cancelAnimation() {
    animation?.task.cancel()
    animation = nil
  }

  private func completeAnimation(_ id: Int) {
    guard let running = animation, running.id == id else { return }
    animation = nil
    place(running.finals)
  }

  private func nudge(_ windowID: WindowID, to origin: CGPoint) {
    rememberOriginalFrame(of: windowID)
    do {
      try backend.setPosition(origin, of: windowID)
    } catch {
      // One missed frame is invisible; the final placement reports real failures.
      Self.log.debug("cannot slide window \(windowID.rawValue): \(error.description)")
    }
  }

  // MARK: - Restoring

  /// Brings every parked window back to where it was before mwmd moved it and empties the
  /// other monitors. The current monitor keeps its list (so `tiling on` restores its order) and
  /// its windows stay where they are.
  func unparkAll() {
    for index in monitors.indices where index != monitors.currentIndex {
      restoreOriginalFrames(of: monitors[index].windows)
      monitors[index].sync(eligible: [])
    }
  }

  /// Moves windows back to their original frames. Windows mwmd never moved are skipped.
  /// Failures are logged and don't stop the others.
  @discardableResult
  func restoreOriginalFrames(of windowIDs: [WindowID]) -> Int {
    var failures = 0
    for windowID in windowIDs {
      guard let frame = originalFrames[windowID] else { continue }
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
