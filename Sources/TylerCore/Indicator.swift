import CoreGraphics

/// Everything an indicator (a menu bar item) may show: the workspaces, whether tiling runs, the
/// area windows are tiled in, and which items the config file turns on. Raw state, with no
/// titles or symbols: each indicator derives what it draws, and redraws only when that changed.
public struct IndicatorSnapshot: Equatable, Sendable {
  public var row: WorkspaceRow
  public var tiling: ServerStatus.Tiling
  /// The primary display's visible frame, or `nil` when no display is known.
  public var area: CGRect?
  public var settings: Config.Indicator
  /// The process of each tiled window's app, so an indicator can show the app's icon.
  public var processIDs: [WindowID: Int32]

  public init(
    row: WorkspaceRow, tiling: ServerStatus.Tiling, area: CGRect? = nil,
    settings: Config.Indicator = Config.Indicator(), processIDs: [WindowID: Int32] = [:]
  ) {
    self.row = row
    self.tiling = tiling
    self.area = area
    self.settings = settings
    self.processIDs = processIDs
  }
}

/// Shows the workspaces somewhere the user can see them (the menu bar). The manager calls `show`
/// whenever the snapshot changes, and once at the start.
@MainActor
public protocol Indicator: AnyObject {
  func show(_ snapshot: IndicatorSnapshot)
}
