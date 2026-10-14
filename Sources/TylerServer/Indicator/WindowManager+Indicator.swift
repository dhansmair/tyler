import TylerCore
import TylerProtocol

/// Keeping the menu bar indicators in step with the workspaces.
extension WindowManager {
  /// Tells the indicator about the workspaces, if the snapshot has changed. Cheap enough to run
  /// on every change to the workspaces, which is when it runs. Each indicator redraws only when
  /// what it draws changed.
  func updateIndicator() {
    guard let indicator else { return }
    let current = IndicatorSnapshot(
      row: workspaces, tiling: tilingStatus, area: focusedDisplay?.visibleFrame,
      settings: config.indicators, apps: tiledApps, layoutCycle: config.layouts.cycle)
    guard current != shownSnapshot else { return }
    shownSnapshot = current
    indicator.show(current)
  }

  /// The app of every window on a workspace. A window's app never changes, and a window is in
  /// the registry before it joins a workspace, so this is complete whenever the workspaces
  /// change.
  private var tiledApps: [WindowID: IndicatorSnapshot.App] {
    var apps: [WindowID: IndicatorSnapshot.App] = [:]
    for workspace in workspaces.workspaces {
      for windowID in workspace.windows {
        guard let window = registry.window(withID: windowID) else { continue }
        apps[windowID] = IndicatorSnapshot.App(
          processID: window.processID, name: window.appName, bundleID: window.bundleID,
          icon: config.icon(bundleID: window.bundleID, appName: window.appName))
      }
    }
    return apps
  }
}
