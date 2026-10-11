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

  /// The connected display named `key`, if any.
  func display(for key: DisplayKey) -> DisplayInfo? {
    displays.displays.first { $0.key == key }
  }
}
