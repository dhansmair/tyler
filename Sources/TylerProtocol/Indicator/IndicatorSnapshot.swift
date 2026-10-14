import CoreGraphics
import TylerConfig
import TylerCore

/// Everything an indicator (a menu bar item) may show: the workspaces, whether tiling runs, the
/// area windows are tiled in, and which items the config file turns on. Raw state, with no
/// titles or symbols: each indicator derives what it draws, and redraws only when that changed.
package struct IndicatorSnapshot: Equatable, Sendable {
  /// The app a tiled window belongs to.
  package struct App: Equatable, Sendable {
    package var processID: Int32
    package var name: String
    package var bundleID: String?
    /// What the config file shows on the app's windows instead of its icon (`apps.<app>.icon`).
    package var icon: IndicatorIcon?

    package init(
      processID: Int32, name: String, bundleID: String? = nil, icon: IndicatorIcon? = nil
    ) {
      self.processID = processID
      self.name = name
      self.bundleID = bundleID
      self.icon = icon
    }
  }

  package var row: WorkspaceRow
  package var tiling: ServerStatus.Tiling
  /// The primary display's visible frame, or `nil` when no display is known.
  package var area: CGRect?
  package var settings: Config.Indicators
  /// Each tiled window's app, so an indicator can show its icon.
  package var apps: [WindowID: App]
  /// The layouts `layout next` goes through, so the menu can say which comes next.
  package var layoutCycle: [LayoutKind]

  package init(
    row: WorkspaceRow, tiling: ServerStatus.Tiling, area: CGRect? = nil,
    settings: Config.Indicators = Config.Indicators(), apps: [WindowID: App] = [:],
    layoutCycle: [LayoutKind] = LayoutKind.defaultCycle
  ) {
    self.row = row
    self.tiling = tiling
    self.area = area
    self.settings = settings
    self.apps = apps
    self.layoutCycle = layoutCycle
  }
}
