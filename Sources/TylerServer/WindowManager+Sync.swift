import CoreGraphics
import TylerCore

/// Keeping the workspaces' lists in line with the windows that exist, and sending new windows
/// to the workspace their app is assigned to.
extension WindowManager {
  struct SyncOutcome {
    /// Whether the list of the focused display's current workspace changed. Other displays whose
    /// current workspace changed are laid out by the sync itself.
    var changedCurrent = false
    /// The parked workspace that the focused window was just assigned to, if any: its display
    /// and its index in that display's row.
    var focusedArrival: (key: DisplayKey, index: Int)?
  }

  /// Updates every workspace's list on every display (see `WorkspaceSync` for the rules), parks
  /// windows that arrive on a workspace that isn't on screen, and remembers every window that
  /// has been on a workspace, so app assignments leave it alone from then on. First the rows
  /// follow the connected displays (see `DisplayRows.reassign`). While the displays are
  /// changing, nothing changes: macOS is still moving windows between displays, and
  /// `displaysSettled` syncs once it is done. Windows in `held` keep their workspace wherever
  /// they are.
  @discardableResult
  func syncWorkspaces(holding held: Set<WindowID> = []) -> SyncOutcome {
    guard displaySettling == nil else { return SyncOutcome() }
    let connected = connectedDisplays
    rows.reassign(to: connected.map(\.key), configured: configuredNumbers(config))
    guard
      let syncs = WorkspaceSync.plan(
        for: rows, windows: registry.windows, displays: connected,
        marks: WorkspaceSync.Marks(
          floated: bookkeeping.floated, seen: bookkeeping.seen,
          // Strip windows out of view are parked like other workspaces' windows.
          sliding: animatingWindows.union(offViewWindows),
          // A dragged window stays on its workspace until it is dropped, even while it is over
          // another display.
          held: held.union(drag.map { [$0.windowID] } ?? [])),
        assignedWorkspace: {
          self.config.assignedWorkspace(bundleID: $0.bundleID, appName: $0.appName)
        })
    else { return SyncOutcome() }
    var outcome = SyncOutcome()
    var changedElsewhere: Set<DisplayKey> = []
    for (position, sync) in syncs.enumerated() {
      let key = rows.entries[position].key
      for index in rows[position].indices {
        let changed = rows[position][index].sync(eligible: sync.eligible[index])
        guard changed && index == rows[position].currentIndex else { continue }
        if key == rows.focusedKey {
          outcome.changedCurrent = true
        } else {
          changedElsewhere.insert(key)
        }
      }
      park(sync.arrivals)
    }
    // Only the focused display slides, so the others can be laid out at once, whatever the
    // caller does with the focused one.
    if isTiling && !changedElsewhere.isEmpty { applyLayout(on: changedElsewhere) }
    bookkeeping.seen.formUnion(rows.allWindows)
    let arrivals = Set(syncs.flatMap(\.arrivals))
    if let focusedID = registry.focusedID, arrivals.contains(focusedID) {
      outcome.focusedArrival = rows.location(of: focusedID).map { location in
        (rows.entries[location.position].key, location.index)
      }
    }
    return outcome
  }

  /// Moves windows of parked workspaces straight to their parking spot, without a slide.
  func park(_ windowIDs: [WindowID]) {
    place(windowIDs.compactMap(parkingPlacement(of:)))
  }

  /// Where a window of a parked workspace waits: the parking spot of its slot in that workspace,
  /// on that workspace's display. A window arriving from another display then waits at a height
  /// where that display is, ready to slide in. `nil` if it isn't on a workspace or its display
  /// isn't connected.
  func parkingPlacement(of windowID: WindowID) -> Placement? {
    guard let location = rows.location(of: windowID), let display = display(at: location.position),
      let window = registry.window(withID: windowID)
    else { return nil }
    let workspace = rows[location.position][location.index]
    let slot =
      workspace.placements(in: display.visibleFrame, gaps: gaps).first { $0.id == windowID }?.frame
      ?? CGRect(origin: display.visibleFrame.origin, size: window.frame.size)
    return Placement(id: windowID, frame: Parking.frame(for: slot, on: display))
  }
}
