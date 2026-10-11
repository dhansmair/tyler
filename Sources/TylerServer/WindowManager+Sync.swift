import CoreGraphics
import TylerCore

/// Keeping the workspaces' lists in line with the windows that exist, and sending new windows
/// to the workspace their app is assigned to.
extension WindowManager {
  struct SyncOutcome {
    /// Whether the list of any display's current workspace changed.
    var changedCurrent = false
    /// The parked workspace that the focused window was just assigned to, if it is on the
    /// focused display.
    var focusedArrival: Int?
  }

  /// Updates every workspace's list on every display (see `WorkspaceSync` for the rules), parks
  /// windows that arrive on a workspace that isn't on screen, and remembers every window that
  /// has been on a workspace, so app assignments leave it alone from then on. First the rows
  /// follow the connected displays (see `DisplayRows.reassign`).
  @discardableResult
  func syncWorkspaces() -> SyncOutcome {
    let connected = connectedDisplays
    rows.reassign(to: connected.map(\.key), configured: configuredNumbers(config))
    guard
      let syncs = WorkspaceSync.plan(
        for: rows, windows: registry.windows, displays: connected,
        marks: WorkspaceSync.Marks(
          floated: bookkeeping.floated, seen: bookkeeping.seen,
          // Strip windows out of view are parked like other workspaces' windows.
          sliding: animatingWindows.union(offViewWindows)),
        assignedWorkspace: {
          self.config.assignedWorkspace(bundleID: $0.bundleID, appName: $0.appName)
        })
    else { return SyncOutcome() }
    var outcome = SyncOutcome()
    for (position, sync) in syncs.enumerated() {
      for index in rows[position].indices {
        let changed = rows[position][index].sync(eligible: sync.eligible[index])
        if changed && index == rows[position].currentIndex { outcome.changedCurrent = true }
      }
      if let display = display(at: position) { park(sync.arrivals, on: display) }
    }
    bookkeeping.seen.formUnion(rows.allWindows)
    let arrivals = syncs.flatMap(\.arrivals)
    if let focusedID = registry.focusedID, arrivals.contains(focusedID) {
      outcome.focusedArrival = workspaces.index(containing: focusedID)
    }
    return outcome
  }

  /// Moves windows straight to their parking spot, without a slide.
  private func park(_ windowIDs: [WindowID], on display: DisplayInfo) {
    place(
      windowIDs.compactMap { windowID in
        registry.window(withID: windowID).map { window in
          Placement(id: windowID, frame: Parking.frame(for: window.frame, on: display))
        }
      })
  }
}
