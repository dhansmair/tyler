import CoreGraphics
import TylerConfig
import TylerCore
import TylerProtocol

extension Response {
  init(_ refusal: Refusal) {
    switch refusal {
    case .message(let text): self = .message(text)
    case .error(let text): self = .error(text)
    }
  }
}

/// What a controller may read besides the model: the windows, the displays and the config, as
/// they are when it runs.
struct ControllerContext {
  let registry: WindowRegistry
  /// In the order tyler numbers them (see `DisplayArrangement`).
  let displays: [DisplayInfo]
  let config: Config
  var isRunning = true
  /// Sliding now, or that a swipe may move.
  var movingWindows: Set<WindowID> = []
  var dragSession: DragSession?
  /// Sent to another display, their move not reported back yet (see `WindowMover.crossing`).
  var crossingWindows: Set<WindowID> = []
  /// The displays changed and macOS is still moving windows between them.
  var isSettling = false
  var slideDuration = Animator.defaultDuration
  var isPrimaryButtonDown = false
  /// No slide or swipe moves the windows.
  var allowsDrag = true

  var gaps: LayoutGaps { LayoutGaps(config.gaps) }

  func isTiling(_ model: Model) -> Bool { isRunning && model.tilingEnabled }

  var draggedWindow: WindowID? { dragSession?.windowID }

  /// What ends whatever moves the windows, worked out against `model` as it is now: a slide jumps
  /// to its end, a swipe's windows go back where they started, and what a drag's preview moved
  /// goes back to its slot, once the preview has stopped moving it.
  func endInteractionEffects(_ model: Model) -> [Effect] {
    guard var session = dragSession else { return [.endSlideOrSwipe] }
    return [.endSlideOrSwipe, .forgetDrag]
      + DragController(context: self).endingEffects(&session, model: model)
  }

  /// This context once `endInteractionEffects` have run, for a decision that comes after them.
  var endingInteraction: ControllerContext {
    var context = self
    context.movingWindows = []
    context.dragSession = nil
    return context
  }

  /// Each window to its parking spot on its workspace's display, keeping its size.
  func parking(_ windowIDs: [WindowID], in rows: DisplayRows) -> Effect {
    let tiling = TilingSnapshot(rows: rows, displays: displays, gaps: gaps)
    return .place(
      windowIDs.compactMap { windowID in
        registry.window(withID: windowID).flatMap {
          tiling.parkingPlacement(of: windowID, size: $0.frame.size)
        }
      })
  }

  func display(for key: DisplayKey) -> DisplayInfo? {
    displays.first { $0.key == key }
  }

  func moves(toward desired: [Placement]) -> [Placement] {
    Reconciler.moves(toward: desired) { registry.window(withID: $0)?.frame }
  }

  func isInPlace(_ placement: Placement) -> Bool {
    moves(toward: [placement]).isEmpty
  }

  /// The focused display's current workspace before a change, to animate the change as a scroll.
  func viewSnapshot(of rows: DisplayRows) -> ViewSnapshot? {
    display(for: rows.focusedKey).map { ViewSnapshot(rows.focused.current, on: $0, gaps: gaps) }
  }
}
