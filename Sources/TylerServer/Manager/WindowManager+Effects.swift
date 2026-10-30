import CoreGraphics
import TylerCore
import TylerProtocol

extension WindowManager {
  var context: ControllerContext {
    ControllerContext(
      registry: registry, displays: connectedDisplays, config: config, log: log,
      isRunning: state == .running, movingWindows: animatingWindows,
      dragSession: drag?.session, crossingWindows: mover.crossing,
      isSettling: displaySettling.isPending, slideDuration: animator.duration,
      isPrimaryButtonDown: pointer?.isPrimaryButtonDown ?? false,
      allowsDrag: interaction.allowsDrag)
  }

  @discardableResult
  func run(_ effects: [Effect]) -> Setbacks {
    var setbacks = Setbacks()
    var hasMoved = false
    defer { if hasMoved { refreshGapCursor() } }
    for effect in effects {
      switch effect {
      case .reconcile, .place, .placeInPassing, .nudge, .carry, .carryFrame, .animate, .preview,
        .restoreOriginalFrames:
        setbacks.unplaced += move(effect)
        hasMoved = true
      case .focus, .focusCurrentWorkspace:
        focus(effect, &setbacks)
      case .endSlideOrSwipe, .forgetDrag, .releaseCrossings, .applyPointerSettings,
        .rememberOriginalFrames:
        updateState(effect)
      case .close(let windowID):
        setbacks.closeFailure = close(windowID)
      case .findMissedWindows:
        windowSystem.trackUntrackedWindows()
      }
    }
    return setbacks
  }

  /// Returns how many windows could not be placed.
  private func move(_ effect: Effect) -> Int {
    switch effect {
    case .reconcile(let force, let keys): reconcileWindows(force: force, on: keys)
    case .place(let placements): place(placements)
    case .placeInPassing(let placements): mover.place(placements, inPassing: true, known: registry)
    case .nudge(let nudges): nudge(nudges)
    case .carry(let nudge): carry(nudge)
    case .carryFrame(let placement): carry(placement)
    case .animate(let transition): animate(transition)
    case .preview(let placements, let duration): preview(placements, over: duration)
    case .restoreOriginalFrames(let windowIDs): restoreOriginalFrames(of: windowIDs)
    case .focus, .focusCurrentWorkspace, .endSlideOrSwipe, .forgetDrag, .releaseCrossings,
      .applyPointerSettings, .rememberOriginalFrames, .close, .findMissedWindows:
      0
    }
  }

  private func focus(_ effect: Effect, _ setbacks: inout Setbacks) {
    switch effect {
    case .focus(let windowID):
      do {
        try requestFocus(windowID)
      } catch {
        setbacks.focusFailure = FocusFailure(windowID: windowID, error: error)
      }
    case .focusCurrentWorkspace:
      if let problem = focusCurrentWorkspace() { setbacks.unfocused = problem }
    case .reconcile, .place, .placeInPassing, .nudge, .carry, .carryFrame, .animate, .preview,
      .restoreOriginalFrames,
      .endSlideOrSwipe, .forgetDrag, .releaseCrossings, .applyPointerSettings,
      .rememberOriginalFrames, .close, .findMissedWindows:
      break
    }
  }

  private func updateState(_ effect: Effect) {
    switch effect {
    case .endSlideOrSwipe: endSlideOrSwipe()
    case .forgetDrag: forgetDrag()
    case .releaseCrossings(let windowIDs): mover.release(windowIDs)
    case .rememberOriginalFrames(let frames): mover.remember(originalFrames: frames)
    case .applyPointerSettings: applyPointerSettings()
    case .reconcile, .place, .placeInPassing, .nudge, .carry, .carryFrame, .animate, .preview,
      .restoreOriginalFrames,
      .focus, .focusCurrentWorkspace, .close, .findMissedWindows:
      break
    }
  }

  /// Returns why the window didn't close, if it didn't.
  private func close(_ windowID: WindowID) -> String? {
    do {
      try mover.close(windowID, known: registry)
      return nil
    } catch {
      log.error("window closing failed - \(named(windowID)) - \(error.description)")
      return "cannot close window \(windowID.rawValue): \(error.description)"
    }
  }

  /// Focuses the current workspace's focused window, or takes the focus from a parked window if
  /// the workspace has none. While the displays settle the lists keep windows that closed, so
  /// only a window still there counts. Returns why that failed, if it did, for the command's
  /// reply.
  @discardableResult
  func focusCurrentWorkspace() -> String? {
    let workspace = workspaces.current
    let candidates = [workspace.focused].compactMap { $0 } + workspace.windows
    guard let target = candidates.first(where: { registry.window(withID: $0) != nil }) else {
      return unfocusParkedWindow()
    }
    do {
      try requestFocus(target)
      return nil
    } catch {
      let problem = "cannot focus window \(target.rawValue): \(error.description)"
      log.error("window focusing failed - \(named(target)) - \(error.description)")
      return problem
    }
  }

  /// An empty workspace has nothing to focus, but the window that had focus (parked now, or on
  /// another display) would still get every key typed. A floated window stays on screen, so it
  /// keeps focus.
  private func unfocusParkedWindow() -> String? {
    guard let focusedID = registry.focusedID, rows.location(of: focusedID) != nil else {
      return nil
    }
    do {
      try mover.unfocus()
      return nil
    } catch {
      let problem = "cannot take focus from window \(focusedID.rawValue): \(error.description)"
      log.error("window unfocusing failed - \(named(focusedID)) - \(error.description)")
      return problem
    }
  }

  func respond(_ decide: () throws(Refusal) -> Decision) -> Response {
    let decision: Decision
    do {
      decision = try decide()
    } catch {
      return Response(error)
    }
    let setbacks = run(decision.effects)
    if let failure = setbacks.focusFailure { return .error(failure.description) }
    if let failure = setbacks.closeFailure { return .error(failure) }
    return outcome(decision.summary, setbacks)
  }

  @discardableResult
  func reconcileWindows(force: Bool = false, on keys: Set<DisplayKey>? = nil) -> Int {
    let desired = tiling.restingPlacements(on: keys)
    let moves = Reconciler.moves(toward: desired) { registry.window(withID: $0)?.frame }
    return place(force ? desired : moves)
  }

  @discardableResult
  func restoreOriginalFrames(of windowIDs: [WindowID]) -> Int {
    mover.restoreOriginalFrames(of: windowIDs, known: registry)
  }
}
