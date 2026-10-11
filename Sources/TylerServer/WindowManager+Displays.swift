import TylerCore

/// The displays and their rows of workspaces.
extension WindowManager {
  /// The focused display's row, which commands act on.
  var workspaces: WorkspaceRow {
    get { rows.focused }
    _modify { yield &rows.focused }
  }

  /// The display commands act on: the one of the focused window, or the one a command last
  /// went to; `nil` while it isn't connected.
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

  /// Makes the display holding the workspace numbered `number` the one commands act on. Returns
  /// whether that changed which display it is.
  @discardableResult
  func focusDisplay(holding number: Int) -> Bool {
    guard let location = rows.location(ofNumber: number) else { return false }
    return focusDisplay(at: location.position)
  }

  /// Makes the display of `windowID` the one commands act on: the display of its workspace, or,
  /// for a window on no workspace (floated, a dialog), the display it is on. Returns whether
  /// that changed which display it is.
  @discardableResult
  func focusDisplay(of windowID: WindowID) -> Bool {
    if let location = rows.location(of: windowID) { return focusDisplay(at: location.position) }
    guard let frame = registry.window(withID: windowID)?.frame,
      let key = DisplayGeometry.display(containing: frame, in: displays.displays)?.key,
      let position = rows.position(of: key)
    else { return false }
    return focusDisplay(at: position)
  }

  private func focusDisplay(at position: Int) -> Bool {
    let key = rows.entries[position].key
    guard key != rows.focusedKey else { return false }
    rows.focus(key)
    return true
  }

  /// Records that `windowID` got focus, in whichever display's row holds it.
  func recordFocus(_ windowID: WindowID) {
    guard let location = rows.location(of: windowID) else { return }
    rows[location.position].setFocus(windowID)
  }

  // MARK: - Reconfiguration

  /// How long tylerd waits after the last display change before it acts. macOS sends each
  /// change as a burst over about 0.3 s, and one second after the last one `NSScreen` is up to
  /// date and macOS has finished moving windows (measured in M5's spike S2).
  static let displaySettleDelay = Duration.seconds(1)

  /// Starts following display changes.
  func startDisplays() {
    let changes = displays.changes
    displayPump = Task { [weak self] in
      for await _ in changes {
        self?.displaysChanged()
      }
    }
  }

  /// Stops following display changes, dropping one still pending.
  func stopDisplays() {
    displayPump?.cancel()
    displayPump = nil
    displaySettling?.cancel()
    displaySettling = nil
  }

  /// Notes a display change and (re)starts the wait for the displays to settle, so a burst of
  /// changes is acted on once, after the last one.
  func displaysChanged() {
    displaySettling?.cancel()
    let clock = clock  // Swift opens the existential from a local, not from the stored property.
    displaySettling = Task { [weak self] in
      do {
        try await clock.sleep(for: Self.displaySettleDelay)
      } catch {
        return  // Cancelled: a later change restarted the wait, or tylerd stopped.
      }
      self?.displaysSettled()
    }
  }

  /// Once the displays have settled: ends any slide or drag, moves each workspace to the
  /// display it now belongs on (see `DisplayRows.reassign`) and places every window again,
  /// parked ones included, because macOS moves windows when displays change, and also pulls
  /// parked windows back on screen.
  func displaysSettled() {
    displaySettling = nil
    guard state == .running else { return }
    finishAnimation()
    endDrag()
    let connected = connectedDisplays
    Self.log.info(
      "displays changed: \(connected.map(\.key.rawValue).joined(separator: ", "), privacy: .public)"
    )
    guard tilingEnabled else {
      rows.reassign(to: connected.map(\.key), configured: configuredNumbers(config))
      return
    }
    // The windows macOS moved stay on their workspaces: only windows that came or went
    // meanwhile change the lists.
    syncWorkspaces(holding: rows.allWindows)
    placeEveryWindow()
  }

  /// Puts every window of every display back: those of each current workspace into their
  /// slots, the others at their parking spots, even those that look to be there already.
  @discardableResult
  func placeEveryWindow() -> Int {
    var parked: [WindowID] = []
    for position in rows.entries.indices {
      let row = rows[position]
      for index in row.indices where index != row.currentIndex {
        parked += row[index].windows
      }
    }
    return applyLayout(force: true) + place(parked.compactMap(parkingPlacement(of:)))
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
