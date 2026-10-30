import TylerCore

/// Following a focus tylerd didn't ask for, and waiting for one on a parked window to last.
extension WindowManager {
  func followFocus(to windowID: WindowID, isEcho: Bool) {
    if parkedFocus.isPending {
      log.debug("window focus dropped - the focus moved on to \(named(windowID))")
    }
    parkedFocus.cancel()
    guard !isEcho, workspaceController.isParked(windowID, in: model) else {
      run(workspaceController.focusChanged(to: windowID, isEcho: isEcho, model: &model))
      return
    }
    parkedFocus.restart(after: WorkspaceController.parkedFocusSettling) { [weak self] in
      guard let self else { return }
      run(workspaceController.focusChanged(to: windowID, isEcho: false, model: &model))
    }
  }
}
