import TylerCore

/// Following a focus tylerd didn't ask for, and waiting for one on a parked window to last.
extension WindowManager {
  func followFocus(to windowID: WindowID, isEcho: Bool, from previous: FocusedWindow?) {
    if parkedFocus.isPending {
      log.debug("window focus dropped - the focus moved on to \(named(windowID))")
    }
    guard !isEcho, workspaceController.isParked(windowID, in: model) else {
      parkedFocus.cancel()
      run(workspaceController.focusChanged(to: windowID, isEcho: isEcho, model: &model))
      return
    }
    parkedFocus.restart(after: WorkspaceController.parkedFocusSettling, from: previous) {
      [weak self] origin in
      guard let self else { return }
      let isGone = origin.map { !isStillThere($0.id) } ?? false
      run(
        workspaceController.focusSettled(
          on: windowID, from: origin, previousIsGone: isGone, model: &model))
    }
  }

  /// macOS focuses the next window within 1 ms of a close (`macos-behaviour.md`, "An app's focus
  /// across displays"). If it focuses none, as when an app's last window closes, the closed window
  /// must not count against a focus long after, which is the user's.
  func focusedWindowClosed(_ windowID: WindowID) {
    guard interpreter.lastFocused?.id == windowID else { return }
    closedFocus.restart(after: WorkspaceController.closedFocusMemory) { [weak self] in
      self?.interpreter.forgetFocus(of: windowID)
    }
  }

  func isStillThere(_ windowID: WindowID) -> Bool {
    registry.window(withID: windowID) != nil && stacking?.containsWindow(windowID) != false
  }
}
