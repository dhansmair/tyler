import TylerCore

/// The displays and their rows of workspaces.
extension WindowManager {
  /// The focused display's row, which commands act on.
  var workspaces: WorkspaceRow {
    get { rows.focused }
    _modify { yield &rows.focused }
  }

  /// The display commands act on (for now always the primary one, which holds the only row);
  /// `nil` while it isn't connected.
  var focusedDisplay: DisplayInfo? { display(for: rows.focusedKey) }

  /// The workspace numbers the config gives each display. For now tylerd keeps one row, the
  /// primary display's, so the workspaces of the other displays it lists live there too.
  static func configuredNumbers(_ config: Config) -> [[Int]] {
    config.workspaceNumbers(displayCount: 1)
  }

  /// The connected display named `key`, if any.
  func display(for key: DisplayKey) -> DisplayInfo? {
    displays.displays.first { $0.key == key }
  }
}
