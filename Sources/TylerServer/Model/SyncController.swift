import CoreGraphics
import TylerCore

/// Keeps the workspaces' lists in line with the windows that exist, and sends new windows to the
/// workspace their app is assigned to (see `WorkspaceSync` for the rules).
struct SyncController {
  struct Outcome {
    /// Whether the list of the focused display's current workspace changed. Other displays whose
    /// current workspace changed are laid out by the sync's own effects.
    var changedCurrent = false
    /// The parked workspace that the focused window was just assigned to, if any: its display
    /// and its index in that display's row.
    var focusedArrival: (key: DisplayKey, index: Int)?
    var effects: [Effect] = []
  }

  let context: ControllerContext

  /// First the rows follow the connected displays (see `DisplayRows.reassign`). Windows that
  /// arrive on a workspace that isn't on screen are parked, and every window that has been on a
  /// workspace is remembered, so app assignments leave it alone from then on. While the displays
  /// are settling nothing changes: macOS is still moving windows between them. Windows in `held`
  /// keep their workspace wherever they are.
  func sync(model: inout Model, holding held: Set<WindowID> = []) -> Outcome {
    guard !context.isSettling else { return Outcome() }
    let connected = context.displays
    model.rows.reassign(
      to: connected.map(\.key),
      configured: context.config.workspaceNumbers(displayCount: max(1, connected.count)))
    var outcome = Outcome(effects: restoreLateWindows(model: &model))
    let isFocusUnlisted = context.registry.focusedID.map { model.rows.location(of: $0) == nil }
    let arrived = arrivedCrossings(in: model.rows)
    if !arrived.isEmpty { outcome.effects.append(.releaseCrossings(arrived)) }
    let tiling = TilingSnapshot(rows: model.rows, displays: connected, gaps: context.gaps)
    guard
      let syncs = WorkspaceSync.plan(
        for: model.rows, windows: context.registry.windows, displays: connected,
        marks: WorkspaceSync.Marks(
          floated: model.bookkeeping.floated, seen: model.bookkeeping.seen,
          // Windows out of view in a scrolling layout are parked like other workspaces' windows.
          sliding: context.movingWindows.union(tiling.offViewWindows),
          held: held.union(context.draggedWindow.map { [$0] } ?? [])
            .union(context.crossingWindows.subtracting(arrived))),
        assignedWorkspace: {
          context.config.assignedWorkspace(bundleID: $0.bundleID, appName: $0.appName)
        })
    else { return outcome }
    var changedElsewhere: Set<DisplayKey> = []
    for (position, sync) in syncs.enumerated() {
      let key = model.rows.entries[position].key
      for index in model.rows[position].indices {
        let changed = model.rows[position][index].sync(eligible: sync.eligible[index])
        guard changed && index == model.rows[position].currentIndex else { continue }
        if key == model.rows.focusedKey {
          outcome.changedCurrent = true
        } else {
          changedElsewhere.insert(key)
        }
      }
      if !sync.arrivals.isEmpty {
        outcome.effects.append(context.parking(sync.arrivals, in: model.rows))
      }
    }
    // Only the focused display slides, so the others are laid out at once, whatever the caller
    // does with the focused one.
    if context.isTiling(model) && !changedElsewhere.isEmpty {
      let placements = TilingSnapshot(rows: model.rows, displays: connected, gaps: context.gaps)
        .restingPlacements(on: changedElsewhere)
      outcome.effects.append(.place(context.moves(toward: placements)))
    }
    model.bookkeeping.seen.formUnion(model.rows.allWindows)
    outcome.focusedArrival = followFocus(
      wasUnlisted: isFocusUnlisted == true, arrivals: Set(syncs.flatMap(\.arrivals)),
      model: &model)
    return outcome
  }

  /// Puts windows a previous tylerd handed over that appeared only now back where they were.
  private func restoreLateWindows(model: inout Model) -> [Effect] {
    let late = model.lateHandOver.restore(
      context.registry.windows, into: &model.rows, floated: &model.bookkeeping.floated)
    model.bookkeeping.seen.formUnion(late.restored)
    return late.originalFrames.isEmpty ? [] : [.rememberOriginalFrames(late.originalFrames)]
  }

  /// A new window's focus event often comes before the window is tileable, when there was no
  /// list to record it on, so it is recorded once the window is listed. Returns where the focused
  /// window went if it was assigned to a parked workspace.
  private func followFocus(
    wasUnlisted: Bool, arrivals: Set<WindowID>, model: inout Model
  ) -> (key: DisplayKey, index: Int)? {
    guard let focusedID = context.registry.focusedID else { return nil }
    if wasUnlisted { model.recordFocus(focusedID) }
    guard arrivals.contains(focusedID) else { return nil }
    return model.rows.location(of: focusedID).map { location in
      (model.rows.entries[location.position].key, location.index)
    }
  }

  /// The windows sent to another display that the registry now shows on their workspace's
  /// display, or that are on no workspace any more.
  private func arrivedCrossings(in rows: DisplayRows) -> Set<WindowID> {
    context.crossingWindows.filter { windowID in
      guard let location = rows.location(of: windowID),
        let frame = context.registry.window(withID: windowID)?.frame
      else { return true }
      return DisplayGeometry.display(containing: frame, in: context.displays)?.key
        == rows.entries[location.position].key
    }
  }
}
