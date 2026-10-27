import CoreGraphics
import TylerCore

/// Moving and resizing with the modifier, or by dragging a gap: the press, then the drag in
/// progress.
extension WindowManager {
  /// The topmost window at `location`, if it is in view (tiled on a display's current
  /// workspace, or floated). Nothing is grabbed with tiling off, while a slide, swipe or drag
  /// runs, or outside every display's visible frame (the menu bar, the Dock).
  func grabbableWindow(at location: CGPoint) -> WindowID? {
    pointerCheck(at: location)?.grab.window
  }

  /// Whether a press that could start a gesture of `kind` at `location` is taken over.
  func decidesCapture(_ kind: ModifierGesture.Kind, at location: CGPoint) -> Bool {
    kind == .gap ? decidesGapGrab(at: location) : decidesGrab(at: location)
  }

  /// Whether a press with the modifier at `location` is taken over, logging why not when it goes
  /// on to the app.
  func decidesGrab(at location: CGPoint) -> Bool {
    let check = pointerCheck(at: location)
    let verdict = check?.grab
    if case .refused(let refusal) = verdict {
      log.info(
        "modifier press passed on - \(pointerLogSubject(location, check)) - \(refusal.explanation)")
    }
    return verdict?.window != nil
  }

  /// Whether a press with no keys at `location` is in a gap with nothing in front of it. Every
  /// click asks, in the tap, so the stacking is read only for a press in a gap.
  func decidesGapGrab(at location: CGPoint) -> Bool {
    guard let stacking, interaction.isIdle,
      DragController(context: context).gap(at: location, model: model) != nil
    else { return false }
    var check = PointerCheck()
    check.topmost = stacking.topmostWindow(at: location)
    guard check.topmost == nil else {
      log.info("gap press passed on - \(pointerLogSubject(location, check)) - is in front")
      return false
    }
    return true
  }

  /// The check at the press may be out of date by now (the event comes through the pointer's
  /// stream): if the window can't be grabbed any more, the gesture does nothing.
  func beginGrab(_ kind: ModifierGesture.Kind, at start: CGPoint) {
    guard kind != .gap else { return beginGapGrab(at: start) }
    guard let windowID = grabbableWindow(at: start),
      let (session, effects) = DragController(context: context).beginGrab(
        kind, of: windowID, at: start, model: &model)
    else {
      log.info("modifier grab skipped - \(Int(start.x)),\(Int(start.y)) - nothing to grab")
      return
    }
    drag = Drag(session: session)
    if let failure = run(effects).focusFailure {
      log.error("window focusing failed - \(named(windowID)) - \(failure.error.description)")
    }
  }

  private func beginGapGrab(at start: CGPoint) {
    let controller = DragController(context: context)
    guard interaction.isIdle, let gap = controller.gap(at: start, model: model),
      let session = controller.beginGapGrab(gap, at: start, model: model)
    else {
      log.info("gap grab skipped - \(Int(start.x)),\(Int(start.y)) - no gap there any more")
      return
    }
    drag = Drag(session: session)
  }

  /// Pointer events come faster than windows move, so the newest location is acted on at most
  /// once per `mouse.follow-interval`; locations arriving in between replace each other.
  func moveGrab(to location: CGPoint) {
    guard drag != nil else { return }
    drag?.pendingLocation = location
    if drag?.throttle.isHolding == false { followPendingLocation() }
  }

  private func followPendingLocation() {
    guard let location = drag?.pendingLocation else {
      drag?.throttle.release()
      return
    }
    drag?.pendingLocation = nil
    mover.frameStarted()
    stepGrab(to: location)
    drag?.throttle.hold(for: .milliseconds(config.mouse.followInterval), on: clock) {
      [weak self] in
      self?.followPendingLocation()
    }
  }

  private func stepGrab(to location: CGPoint) {
    guard var session = drag?.session else { return }
    let (effects, frame) = DragController(context: context).moveGrab(
      to: location, session: &session, model: model)
    drag?.session = session
    run(effects)
    if let frame { follow(session.windowID, to: frame) }
  }

  /// A step still waiting is taken, then the window settles as a window dropped by its title bar
  /// does (into its slot, swapped, or onto another display).
  func endGrab(at location: CGPoint) {
    if drag?.pendingLocation != nil {
      drag?.pendingLocation = nil
      stepGrab(to: location)
    }
    guard let drag, let grab = drag.session.grab else { return }
    if let frame = drag.pendingFrame {
      self.drag?.pendingFrame = nil
      follow(drag.windowID, to: frame)
    }
    drop(at: location)
    run(
      DragController(context: context).settleGrabbed(grab, windowID: drag.windowID, model: model))
  }
}
