import CoreGraphics
import TylerCore

/// What a trackpad swipe moves when it begins, and where it settles when the fingers lift:
/// `SwipeSession` decides each step in between.
struct SwipeController {
  let context: ControllerContext

  /// A swipe acts on the display under the pointer (`location`), which becomes the focused
  /// display. On a workspace whose layout scrolls, it scrolls the view and never switches
  /// workspaces. No session if swiping is off, a drag runs, or there is nowhere to go.
  func begin(
    at location: CGPoint, model: inout Model
  ) -> (session: SwipeSession?, effects: [Effect]) {
    guard context.config.gestures.swipe, context.isTiling(model), context.draggedWindow == nil
    else { return (nil, []) }
    model.focusDisplay(under: location, in: context)
    guard let display = context.display(for: model.rows.focusedKey) else { return (nil, []) }
    if model.rows.focused.current.scrolls {
      let sync = SyncController(context: context).sync(model: &model)
      let row = model.rows.focused
      let scroll = ViewScroll(
        views: row.current.views(in: display.visibleFrame, gaps: context.gaps),
        current: row.current.firstVisible, on: display)
      return (scroll.map { SwipeSession(target: .view($0)) }, sync.effects)
    }
    guard model.rows.focused.count > 1, let prev = model.rows.focused.index(of: .prev),
      let next = model.rows.focused.index(of: .next)
    else { return (nil, []) }
    let sync = SyncController(context: context).sync(model: &model)
    let workspaces = WorkspaceController(context: context)
    let target = SwipeTarget.workspaceRow(
      prev: workspaces.slidePlan(to: prev, direction: .prev, on: display, rows: model.rows),
      next: workspaces.slidePlan(to: next, direction: .next, on: display, rows: model.rows))
    return (SwipeSession(target: target), sync.effects)
  }

  /// The fingers lifted at `velocity`: the windows settle on a neighbouring workspace or view,
  /// or back where they began, and focus moves into the view if it left it.
  func end(_ session: SwipeSession, velocity: Double, model: inout Model) -> [Effect] {
    var session = session
    guard
      let ending = session.end(velocity: velocity, distance: context.config.gestures.swipeDistance)
    else { return [] }
    var effects: [Effect] = [.place(ending.placements)]
    var focusMoves = false
    switch ending.destination {
    case .stay:
      break
    case .workspace(let index):
      model.rows.focused.select(index)
      focusMoves = true
    case .view(let firstVisible):
      focusMoves = model.rows.focused.current.scroll(toFirstVisible: firstVisible)
    }
    if let settle = ending.settle {
      effects.append(.animate(settle.transition(slideDuration: context.slideDuration)))
    }
    if focusMoves { effects.append(.focusCurrentWorkspace) }
    return effects
  }
}
