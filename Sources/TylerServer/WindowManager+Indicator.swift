import TylerCore

/// Keeping the menu bar indicators in step with the workspaces.
extension WindowManager {
  /// Tells the indicator about the workspaces, if the snapshot has changed. Cheap enough to run
  /// on every change to the workspaces, which is when it runs. Each indicator redraws only when
  /// what it draws changed.
  func updateIndicator() {
    guard let indicator else { return }
    let current = IndicatorSnapshot(
      row: workspaces, tiling: tilingStatus, area: primaryDisplay?.visibleFrame,
      settings: config.indicator, processIDs: tiledProcessIDs)
    guard current != shownSnapshot else { return }
    shownSnapshot = current
    indicator.show(current)
  }

  /// The app process of every window on a workspace. A window's process never changes, and a
  /// window is in the registry before it joins a workspace, so this is complete whenever the
  /// workspaces change.
  private var tiledProcessIDs: [WindowID: Int32] {
    var processIDs: [WindowID: Int32] = [:]
    for workspace in workspaces.workspaces {
      for windowID in workspace.windows {
        processIDs[windowID] = registry.window(withID: windowID)?.processID
      }
    }
    return processIDs
  }
}
