import TylerCore

/// The displays and their rows of workspaces.
extension WindowManager {
  /// The focused display's row, which commands act on.
  var workspaces: WorkspaceRow {
    get { rows.focused }
    _modify { yield &rows.focused }
  }

  /// The display commands act on (for now always the primary one); `nil` while it isn't
  /// connected.
  var focusedDisplay: DisplayInfo? { display(for: rows.focusedKey) }

  /// The connected displays in the order tyler numbers them (see `DisplayArrangement`).
  var connectedDisplays: [DisplayInfo] {
    DisplayArrangement.ordered(displays.displays)
  }

  /// The workspace numbers the config gives each of `displayCount` displays (at least one).
  static func configuredNumbers(_ config: Config, displayCount: Int) -> [[Int]] {
    config.workspaceNumbers(displayCount: max(1, displayCount))
  }

  /// The workspace numbers the config gives each connected display.
  func configuredNumbers(_ config: Config) -> [[Int]] {
    Self.configuredNumbers(config, displayCount: displays.displays.count)
  }

  /// Fresh rows for the connected displays, as the config numbers them.
  func freshRows() -> DisplayRows {
    DisplayRows(keys: connectedDisplays.map(\.key), configured: configuredNumbers(config))
  }

  /// The connected display named `key`, if any.
  func display(for key: DisplayKey) -> DisplayInfo? {
    displays.displays.first { $0.key == key }
  }

  /// The display of the row at `position` in `rows`, if connected.
  func display(at position: Int) -> DisplayInfo? {
    display(for: rows.entries[position].key)
  }

  /// Records that `windowID` got focus, in whichever display's row holds it.
  func recordFocus(_ windowID: WindowID) {
    guard let location = rows.location(of: windowID) else { return }
    rows[location.position].setFocus(windowID)
  }

  // MARK: - Listing

  /// All known windows, tagged with their display, workspace, tiling slot and floated state.
  public func windows() -> Response {
    guard state == .running else { return .error(Self.permissionMessage) }
    let connected = connectedDisplays
    let tagged = registry.windows.map { window -> WindowInfo in
      var copy = window
      let display = DisplayGeometry.display(containing: window.frame, in: connected)
      copy.displayID = display?.id
      copy.displayNumber = display.flatMap { display in
        connected.firstIndex { $0.id == display.id }.map { $0 + 1 }
      }
      if let location = rows.location(of: window.id) {
        let row = rows[location.position]
        copy.workspace = row.number(at: location.index)
        copy.slot = row[location.index].slot(of: window.id)
      }
      copy.isFloated = bookkeeping.floated.contains(window.id)
      return copy
    }
    return .windows(tagged)
  }
}
