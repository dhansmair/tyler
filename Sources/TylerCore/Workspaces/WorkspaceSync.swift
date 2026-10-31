import CoreGraphics

/// Works out which windows each workspace should hold, given the windows that exist. Pure: the
/// server applies the result to its workspaces and parks the arrivals.
///
/// A window stays on its workspace while it is tileable and not floated; parked and sliding
/// windows keep their place whatever their frame says. A window on a display's current workspace
/// that moves to another display goes last in that display's current workspace, or leaves the
/// workspaces if that display has no row. Tileable windows that belong to no workspace join the
/// current workspace of the display they are on. If they have never been tiled and their app is
/// assigned to a workspace, they go there instead, and arrive (to be parked) if it isn't on
/// screen; a window that opened since tylerd started joins the display the user is on, since
/// macOS or the app picks where it appears. Windows on a display without a row are left alone.
package struct WorkspaceSync: Equatable, Sendable {
  /// Per workspace, the windows it should hold, as `Workspace.sync(eligible:)` takes them.
  package var eligible: [[WindowID]]
  /// Windows newly assigned to a workspace that isn't on screen.
  package var arrivals: [WindowID]

  /// What the manager knows about windows beyond their `WindowInfo`.
  package struct Marks: Sendable {
    /// Windows the user took out of tiling.
    package var floated: Set<WindowID>
    /// Windows that have been on a workspace; app assignments leave them alone.
    package var seen: Set<WindowID>
    /// Windows that are sliding or that a swipe may move; they keep their place.
    package var sliding: Set<WindowID>
    /// A window the user is dragging; it keeps its place until it is dropped.
    package var held: Set<WindowID>
    /// Windows that were open when tylerd started; they keep the display they are on.
    package var foundAtStart: Set<WindowID>
    /// The display the user is on, where a window that just opened goes.
    package var focusedDisplay: DisplayKey?

    package init(
      floated: Set<WindowID>, seen: Set<WindowID>, sliding: Set<WindowID>,
      held: Set<WindowID> = [], foundAtStart: Set<WindowID> = [],
      focusedDisplay: DisplayKey? = nil
    ) {
      self.floated = floated
      self.seen = seen
      self.sliding = sliding
      self.held = held
      self.foundAtStart = foundAtStart
      self.focusedDisplay = focusedDisplay
    }

    /// Whether a window on no workspace just opened: it has never been on one, and it wasn't
    /// there when tylerd started.
    package static func isNew(
      _ windowID: WindowID, seen: Set<WindowID>, foundAtStart: Set<WindowID>
    ) -> Bool {
      !seen.contains(windowID) && !foundAtStart.contains(windowID)
    }
  }

  /// One sync per display of `rows`, in their order; `nil` while no display is connected: then
  /// nothing is decided, so parked windows aren't forgotten while they are still parked.
  /// `assignedWorkspace` gives the number of the workspace the config assigns a window's app to.
  package static func plan(
    for rows: DisplayRows, windows: [WindowInfo], displays: [DisplayInfo], marks: Marks,
    assignedWorkspace: (WindowInfo) -> Int?
  ) -> [WorkspaceSync]? {
    guard !displays.isEmpty else { return nil }
    let assignments = Dictionary(
      windows.compactMap { window in assignedWorkspace(window).map { (window.id, $0) } },
      uniquingKeysWith: { _, last in last })
    let planner = Planner(
      rows: rows, windows: windows, displays: displays, marks: marks, assignments: assignments)
    return planner.plan()
  }

  /// The sync of a single row on the primary display (the first of `displays`); windows on the
  /// other displays are left alone.
  package static func plan(
    for row: WorkspaceRow, windows: [WindowInfo], displays: [DisplayInfo], marks: Marks,
    assignedWorkspace: (WindowInfo) -> Int?
  ) -> WorkspaceSync? {
    guard let primary = displays.first else { return nil }
    let rows = DisplayRows(
      entries: [DisplayRows.Entry(key: primary.key, row: row)], homes: [:], focusedKey: nil)
    return plan(
      for: rows, windows: windows, displays: displays, marks: marks,
      assignedWorkspace: assignedWorkspace)?.first
  }
}

extension WorkspaceSync {
  /// A workspace: its display's position in the rows, and its index in that row.
  private struct Place: Hashable {
    let position: Int
    let index: Int
  }

  /// Works out one `WorkspaceSync` per display.
  private struct Planner {
    let rows: DisplayRows
    let windows: [WindowInfo]
    let displays: [DisplayInfo]
    let marks: WorkspaceSync.Marks
    /// The number of the workspace each window's app is assigned to, if any.
    let assignments: [WindowID: Int]

    func plan() -> [WorkspaceSync] {
      var (eligible, joining) = keptAndMoved()
      let assigned = rows.allWindows
      for window in windows where !assigned.contains(window.id) && isCandidate(window) {
        guard let place = destination(of: window) else { continue }
        joining[place, default: []].append(window)
      }
      return rows.entries.indices.map { position in
        var sync = WorkspaceSync(eligible: eligible[position], arrivals: [])
        for index in rows[position].indices {
          var arriving = joining[Place(position: position, index: index)] ?? []
          if index != rows[position].currentIndex {
            sync.arrivals += arriving.map(\.id)
          } else if rows[position][index].count == 0 {
            // First fill: left to right, then top to bottom, so the layout matches the screen.
            arriving.sort { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
          }
          sync.eligible[index] += arriving.map(\.id)
        }
        return sync
      }
    }

    /// Per display and workspace, the windows that stay; and the windows that moved to another
    /// display with a row, by the current workspace they go to.
    private func keptAndMoved() -> (eligible: [[[WindowID]]], moved: [Place: [WindowInfo]]) {
      let byID = Dictionary(windows.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
      var eligible = rows.entries.map { entry in entry.row.workspaces.map { _ in [WindowID]() } }
      var moved: [Place: [WindowInfo]] = [:]
      for (position, entry) in rows.entries.enumerated() {
        for index in entry.row.indices {
          for windowID in entry.row[index].windows {
            guard let window = byID[windowID], isCandidate(window) else { continue }
            let onPosition = self.position(of: window)
            if index != entry.row.currentIndex || isPinned(windowID) || onPosition == position {
              eligible[position][index].append(windowID)
            } else if let onPosition {
              moved[current(at: onPosition), default: []].append(window)
            }
          }
        }
      }
      return (eligible, moved)
    }

    private func isCandidate(_ window: WindowInfo) -> Bool {
      window.isTileable && !marks.floated.contains(window.id)
    }

    /// Whether the window keeps its place whatever its frame says: it is sliding or held.
    private func isPinned(_ windowID: WindowID) -> Bool {
      marks.sliding.contains(windowID) || marks.held.contains(windowID)
    }

    /// The position in the rows of the display the window is on, if that display has a row.
    private func position(of window: WindowInfo) -> Int? {
      DisplayGeometry.display(containing: window.frame, in: displays).flatMap {
        rows.position(of: $0.key)
      }
    }

    /// The current workspace of the display at `position`.
    private func current(at position: Int) -> Place {
      Place(position: position, index: rows[position].currentIndex)
    }

    /// Where a window that belongs to no workspace goes: the workspace its app is assigned to, if
    /// it has never been tiled; else the current workspace of its display, if that has a row.
    private func destination(of window: WindowInfo) -> Place? {
      guard let onPosition = position(of: window) else { return nil }
      let number = marks.seen.contains(window.id) ? nil : assignments[window.id]
      if let location = number.flatMap(rows.location(ofNumber:)) {
        return Place(position: location.position, index: location.index)
      }
      let isNew = Marks.isNew(window.id, seen: marks.seen, foundAtStart: marks.foundAtStart)
      let focused = isNew ? marks.focusedDisplay.flatMap(rows.position(of:)) : nil
      return current(at: focused ?? onPosition)
    }
  }
}
