import TylerCore

extension WorkspaceController {
  /// The focus goes to the window that takes `closed`'s place in its list, whatever the app picks
  /// (#126). Called while the lists still hold `closed`. A floated window, or the last one, has no
  /// such window: the workspace's own focus, or none, is what is left.
  func focusedWindowClosed(_ closed: FocusedWindow, model: inout Model) -> [Effect] {
    guard context.isTiling(model), closed.leftTheChoiceToMacOS(isGone: true),
      let location = model.rows.location(showing: closed.id)
    else { return [] }
    let successor = model.rows[location.position][location.index].successor(of: closed.id)
    model.focusDisplay(at: location.position)
    guard let successor else { return [.focusCurrentWorkspace] }
    model.recordFocus(successor)
    guard context.registry.focusedID != successor else { return [] }
    context.log.info(
      "window focus handed on - "
        + "\(WindowInfo.logName(successor, context.registry.window(withID: successor))) - "
        + "the focused window closed")
    return [.focusCurrentWorkspace]
  }
}
