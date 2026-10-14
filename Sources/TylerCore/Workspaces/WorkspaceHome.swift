/// Where a workspace belongs when its display is connected.
package enum WorkspaceHome: Codable, Equatable, Sendable {
  /// The display the config gives it, by number (1 is the primary).
  case configured(Int)
  /// The display it was last moved to with `move-workspace-to-display`.
  case pinned(DisplayKey)
}
