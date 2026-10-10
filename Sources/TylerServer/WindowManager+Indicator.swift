import TylerCore

/// Keeping the menu bar indicator in step with the workspaces.
extension WindowManager {
  /// Tells the indicator about the workspaces, if what it shows has changed. Cheap enough to run
  /// on every change to the workspaces, which is when it runs.
  func updateIndicator() {
    guard let indicator else { return }
    let current = IndicatorState(row: workspaces, tiling: tilingStatus)
    guard current != shownIndicatorState else { return }
    shownIndicatorState = current
    indicator.show(current)
  }
}
