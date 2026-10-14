import CoreGraphics
import TylerCore

/// A drag in progress and its pacing. `DragController` decides what each step does.
///
/// Following a drag moves every other window, one round trip to its app each, and apps like
/// Firefox take long enough that the resize events of a drag pile up faster than they can be
/// followed. So the first resize is followed at once, later ones at most once per
/// `mouse.follow-interval` from the config: frames arriving in between replace each other, and
/// only the newest is followed.
extension WindowManager {
  func followDrag(of window: WindowInfo) {
    guard pointer?.isPrimaryButtonDown == true,
      let step = DragController(context: context).windowUpdated(
        window, session: drag?.session, model: &model)
    else { return }
    if drag == nil {
      drag = Drag(session: step.session)
    } else {
      drag?.session = step.session
    }
    guard let frame = step.pendingFrame else { return }
    drag?.pendingFrame = frame
    if drag?.throttle.isHolding == false { followPendingFrame() }
  }

  func drop(at location: CGPoint) {
    guard var session = drag?.session else { return }
    let controller = DragController(context: context)
    forgetDrag()
    run(controller.drop(at: location, session: &session, model: &model))
  }

  func previewDrop(at location: CGPoint) {
    guard var session = drag?.session else { return }
    let effects = DragController(context: context).previewDrop(
      at: location, session: &session, model: model)
    drag?.session = session
    run(effects)
  }

  /// Forgets the drag, and any step of it still waiting, putting back the windows its preview
  /// moved.
  func endDrag() {
    guard var session = drag?.session else { return }
    let effects = DragController(context: context).endingEffects(&session, model: model)
    forgetDrag()
    run(effects)
  }

  /// Forgets the preview target without moving it, for a window that is gone.
  func forgetPreviewTarget(_ windowID: WindowID) {
    drag?.session.forgetPreviewTarget(windowID)
  }

  /// When the interval is up, a frame that arrived meanwhile is followed the same way; with
  /// none, the next resize is followed at once again.
  func followPendingFrame() {
    guard let windowID = drag?.windowID, let frame = drag?.pendingFrame else {
      drag?.throttle.release()
      return
    }
    drag?.pendingFrame = nil
    mover.frameStarted()
    follow(windowID, to: frame)
    // Held after following, so the interval stays free however long the step took: each resize
    // echoes back as notifications to read, and the dragged window's own, which drive the drag,
    // wait behind them.
    drag?.throttle.hold(for: .milliseconds(config.mouse.followInterval), on: clock) {
      [weak self] in
      self?.followPendingFrame()
    }
  }

  func follow(_ windowID: WindowID, to frame: CGRect) {
    let movesItself = drag?.session.grab == nil
    run(
      DragController(context: context).follow(
        windowID, to: frame, movesItself: movesItself, model: &model))
  }

  func forgetDrag() {
    drag?.throttle.release()
    drag = nil
  }
}
