import CoreGraphics
import TylerCore

/// Sliding windows: into view, out of view, between workspaces and along a scrolling layout's
/// view.
extension WindowManager {
  /// Windows that are sliding right now (or about to be placed at the end of a slide), or that
  /// a trackpad swipe may move.
  var animatingWindows: Set<WindowID> {
    Set(slide?.finals.map(\.id) ?? []).union(swipingWindows)
  }

  /// Returns how many windows could not be placed synchronously; failures during the slide are
  /// logged.
  @discardableResult
  func animate(_ animation: Transition) -> Int {
    endSlideOrSwipe()
    let animator = animation.duration.map(animator.over) ?? animator
    guard animator.stepCount > 0, !animation.tracks.isEmpty else { return place(animation.finals) }
    let failures = place(animation.start)
    slideCount += 1
    let id = slideCount
    let task = Task { [weak self] in
      let frameStarted: () -> Void = { self?.mover.frameStarted() }
      let move: (WindowID, CGPoint, CGSize?) -> Void = { windowID, origin, size in
        guard let size else { return self?.nudge(windowID, to: origin) ?? () }
        self?.step(Placement(id: windowID, frame: CGRect(origin: origin, size: size)))
      }
      let isComplete =
        animation.startProgress == 0 && animation.endProgress == 1
        ? await animator.run(animation.tracks, frameStarted: frameStarted, move: move)
        : await animator.run(
          animation.tracks, from: animation.startProgress, to: animation.endProgress,
          minimumDuration: animation.minimumDuration, frameStarted: frameStarted, move: move)
      if isComplete { self?.completeSlide(id) }
    }
    slide = Slide(id: id, task: task, finals: animation.finals)
    return failures
  }

  /// Ends a slide early: the windows jump to where the slide would have left them.
  func finishSlide() {
    guard let running = slide else { return }
    slide = nil
    running.task.cancel()
    place(running.finals)
  }

  /// Stops a slide and leaves the windows wherever they are.
  func cancelSlide() {
    slide?.task.cancel()
    slide = nil
  }

  private func completeSlide(_ id: Int) {
    guard let running = slide, running.id == id else { return }
    slide = nil
    place(running.finals)
  }

  func nudge(_ windowID: WindowID, to origin: CGPoint) {
    mover.nudge(windowID, to: origin, known: registry)
  }

  func step(_ placement: Placement) {
    mover.step(placement, known: registry)
  }

  /// Returns 0: a failed carry is logged, and the drop places the window anyway.
  func carry(_ nudge: Nudge) -> Int {
    mover.carry(nudge.id, to: nudge.origin, known: registry)
    return 0
  }

  func carry(_ placement: Placement) -> Int {
    mover.carry(placement.id, toFrame: placement.frame, known: registry)
    return 0
  }

  /// Returns 0: a missed step is invisible, and the final placement reports real failures.
  func nudge(_ nudges: [Nudge]) -> Int {
    for nudge in nudges { self.nudge(nudge.id, to: nudge.origin) }
    return 0
  }
}
