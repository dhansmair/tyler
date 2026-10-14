import CoreGraphics
import TylerCore

/// Moving the windows the drag preview shows somewhere else, over `animations.drag-preview`.
extension WindowManager {
  /// Returns how many windows could not be placed. A preview still under way hands its windows
  /// over where they are; each goes on from there, to its new place or to the one it was going
  /// to.
  @discardableResult
  func preview(_ placements: [Placement], over duration: Duration) -> Int {
    // Each move of the pointer asks again; while the target stays the same there is nothing new.
    guard !placements.isEmpty else { return 0 }
    let running = drag?.preview
    running?.task.cancel()
    drag?.preview = nil
    let transition = Transition(
      handingOver: running?.finals ?? [], to: placements,
      from: { running?.frames[$0] ?? registry.window(withID: $0)?.frame }, duration: duration)
    let animator = animator.over(duration)
    guard drag != nil, animator.stepCount > 0, !transition.tracks.isEmpty else {
      return place(transition.finals)
    }
    drag?.previewCount += 1
    let id = drag?.previewCount ?? 0
    let task = Task { [weak self] in
      let frameStarted: () -> Void = { self?.mover.frameStarted() }
      let move: (WindowID, CGPoint, CGSize?) -> Void = { windowID, origin, size in
        self?.stepPreview(windowID, to: origin, size: size)
      }
      let isComplete = await animator.run(
        transition.tracks, frameStarted: frameStarted, move: move)
      if isComplete { self?.completePreview(id) }
    }
    drag?.preview = DragPreview(
      id: id, task: task, finals: transition.finals, frames: transition.startFrames)
    return 0
  }

  /// Stops the preview's windows where it would have left them.
  func finishPreview() {
    guard let running = drag?.preview else { return }
    drag?.preview = nil
    running.task.cancel()
    place(running.finals)
  }

  private func stepPreview(_ windowID: WindowID, to origin: CGPoint, size: CGSize?) {
    guard let frame = drag?.preview?.frames[windowID] else { return }
    let next = CGRect(origin: origin, size: size ?? frame.size)
    if size == nil {
      nudge(windowID, to: origin)
    } else {
      step(Placement(id: windowID, frame: next))
    }
    drag?.preview?.frames[windowID] = next
  }

  private func completePreview(_ id: Int) {
    guard let running = drag?.preview, running.id == id else { return }
    drag?.preview = nil
    place(running.finals)
  }
}
