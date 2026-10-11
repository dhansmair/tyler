import TylerCore

/// Keeping the menu bar indicators in step with the workspaces.
extension WindowManager {
  /// Tells the indicator about the workspaces, if the snapshot has changed. Cheap enough to run
  /// on every change to the workspaces, which is when it runs. Each indicator redraws only when
  /// what it draws changed.
  func updateIndicator() {
    guard let indicator else { return }
    let current = IndicatorSnapshot(
      row: workspaces, tiling: tilingStatus, area: primaryDisplay?.visibleFrame)
    guard current != shownSnapshot else { return }
    shownSnapshot = current
    indicator.show(current)
  }
}
