import CoreGraphics

/// Everything an indicator (a menu bar item) may show: the workspaces, whether tiling runs, and
/// the area windows are tiled in. Raw state, with no titles or symbols: each indicator derives
/// what it draws, and redraws only when that changed.
public struct IndicatorSnapshot: Equatable, Sendable {
  public var row: WorkspaceRow
  public var tiling: ServerStatus.Tiling
  /// The primary display's visible frame, or `nil` when no display is known.
  public var area: CGRect?

  public init(row: WorkspaceRow, tiling: ServerStatus.Tiling, area: CGRect? = nil) {
    self.row = row
    self.tiling = tiling
    self.area = area
  }
}

/// Shows the workspaces somewhere the user can see them (the menu bar). The manager calls `show`
/// whenever the snapshot changes, and once at the start.
@MainActor
public protocol Indicator: AnyObject {
  func show(_ snapshot: IndicatorSnapshot)
}
