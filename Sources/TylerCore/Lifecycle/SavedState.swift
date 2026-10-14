import CoreGraphics
import Foundation

/// The workspaces as tylerd leaves them when it restarts, so the next tylerd can carry on where
/// it stopped instead of tiling everything onto the first workspace. Windows are identified by
/// their `WindowID`, which stays the same while the window lives.
package struct SavedState: Codable, Equatable, Sendable {
  /// Bumped whenever the format changes; a file with another version is ignored. Version 3 keeps
  /// every layout's state as one value; versions 1 and 2 kept each piece in a field of its own.
  /// Version 2 holds a row per display; version 1, with a single row, is still read.
  package static let currentVersion = 3
  /// The versions `read` accepts.
  package static let readableVersions = 1...3

  package struct SavedWorkspace: Codable, Equatable, Sendable {
    package var windows: [WindowID]
    package var focused: WindowID?
    package var layout: LayoutKind
    /// `Workspace.firstVisible`; missing in files from before the strip.
    package var firstVisible: WindowID?
    /// Version 3.
    package var layoutStates: LayoutStates?
    /// Versions 1 and 2: `TallLayoutState.mainRatio`.
    package var mainRatio: Double?
    /// Versions 1 and 2: `TallLayoutState.rowWeights`; missing in files from before mouse
    /// resizing.
    package var rowWeights: [[Double]]?
    /// Versions 1 and 2: the windows' strip sizes; missing in files from before the strip.
    package var sizes: [SavedSize]?
    /// Versions 1 and 2: `GridLayoutState.weights`; missing in files from before the grid.
    package var grid: ColumnWeights?

    /// A workspace as tylerd wrote it before version 3.
    package init(
      windows: [WindowID], focused: WindowID?, layout: LayoutKind, mainRatio: Double,
      rowWeights: [[Double]]? = nil, sizes: [SavedSize]? = nil, firstVisible: WindowID? = nil,
      grid: ColumnWeights? = nil
    ) {
      self.windows = windows
      self.focused = focused
      self.layout = layout
      self.mainRatio = mainRatio
      self.rowWeights = rowWeights
      self.sizes = sizes
      self.firstVisible = firstVisible
      self.grid = grid
    }

    init(_ workspace: Workspace) {
      windows = workspace.windows
      focused = workspace.focused
      layout = workspace.layout
      firstVisible = workspace.firstVisible
      layoutStates = workspace.layoutStates
    }

    var states: LayoutStates {
      if let layoutStates { return layoutStates }
      var strip = StripLayoutState()
      for saved in sizes ?? [] { strip.setSize(saved.size, of: saved.id) }
      return LayoutStates(
        tall: TallLayoutState(mainRatio: mainRatio ?? 0.5, rowWeights: rowWeights ?? []),
        grid: GridLayoutState(weights: grid ?? ColumnWeights()), strip: strip)
    }
  }

  /// A window's size in the strip layout (versions 1 and 2).
  package struct SavedSize: Codable, Equatable, Sendable {
    package var id: WindowID
    package var size: WindowSize

    package init(id: WindowID, size: WindowSize) {
      self.id = id
      self.size = size
    }
  }

  /// One display's row: the display, its workspaces with their numbers, and the one on screen.
  package struct SavedDisplay: Codable, Equatable, Sendable {
    package var key: DisplayKey
    package var numbers: [Int]
    package var workspaces: [SavedWorkspace]
    package var currentIndex: Int

    package init(_ entry: DisplayRows.Entry) {
      key = entry.key
      numbers = entry.row.numbers
      workspaces = entry.row.workspaces.map(SavedWorkspace.init)
      currentIndex = entry.row.currentIndex
    }
  }

  /// Where a workspace belongs when its display is connected.
  package struct SavedHome: Codable, Equatable, Sendable {
    package var number: Int
    package var home: WorkspaceHome
  }

  /// Where a window was before tylerd first moved it.
  package struct OriginalFrame: Codable, Equatable, Sendable {
    package var id: WindowID
    package var frame: CGRect

    package init(id: WindowID, frame: CGRect) {
      self.id = id
      self.frame = frame
    }
  }

  package var version: Int
  /// Each display's row (version 2).
  package var displays: [SavedDisplay]?
  /// Each workspace's home (version 2).
  package var homes: [SavedHome]?
  /// The display commands acted on (version 2).
  package var focusedDisplay: DisplayKey?
  /// The single row of version 1.
  package var workspaces: [SavedWorkspace]?
  /// 0-based, like `WorkspaceRow.currentIndex` (version 1).
  package var currentIndex: Int?
  package var floated: [WindowID]
  package var tilingEnabled: Bool
  package var originalFrames: [OriginalFrame]
  /// Windows that have been tiled, so app assignments leave them alone; missing in files from
  /// before app assignments.
  package var seen: [WindowID]?
  /// When the previous tylerd wrote the file; missing in files from before 0.1.0.
  package var writtenAt: Date?

  /// How old a file may be when it is read. A hand-over takes seconds; an older file was left
  /// behind (the next tylerd never started, or stopped before tracking windows), and window IDs
  /// are reused after a reboot or a new login, so it would name unrelated windows.
  package static let maximumAge: TimeInterval = 60

  package init(
    rows: DisplayRows, floated: Set<WindowID>, tilingEnabled: Bool,
    originalFrames: [WindowID: CGRect], seen: Set<WindowID> = []
  ) {
    version = Self.currentVersion
    displays = rows.entries.map(SavedDisplay.init)
    homes = rows.homes.keys.sorted().compactMap { number in
      rows.homes[number].map { SavedHome(number: number, home: $0) }
    }
    focusedDisplay = rows.focusedKey
    self.floated = floated.sorted()
    self.tilingEnabled = tilingEnabled
    self.originalFrames = originalFrames.keys.sorted().compactMap { windowID in
      originalFrames[windowID].map { OriginalFrame(id: windowID, frame: $0) }
    }
    self.seen = seen.sorted()
  }

  /// A version 1 state, with one row, as a tylerd from before several displays wrote it.
  package init(
    row: WorkspaceRow, floated: Set<WindowID>, tilingEnabled: Bool,
    originalFrames: [WindowID: CGRect], seen: Set<WindowID> = []
  ) {
    self.init(
      rows: DisplayRows(keys: [], configured: []), floated: floated,
      tilingEnabled: tilingEnabled, originalFrames: originalFrames, seen: seen)
    version = 1
    displays = nil
    homes = nil
    focusedDisplay = nil
    workspaces = row.workspaces.map(SavedWorkspace.init)
    currentIndex = row.currentIndex
  }

  /// The windows the previous tylerd had tiled. A file from before app assignments doesn't
  /// list them, so every window it mentions counts.
  package var seenWindows: Set<WindowID> {
    if let seen { return Set(seen) }
    let saved = (workspaces ?? []) + (displays ?? []).flatMap(\.workspaces)
    return Set(saved.flatMap(\.windows) + floated)
  }

  /// A row of `count` workspaces holding the saved windows of a version 1 file that still exist
  /// (`exists`), in their saved order, with their focus, layout, ratio, row weights, strip sizes
  /// and view. Saved workspaces beyond `count` are merged into the last one, as
  /// `WorkspaceRow.setCount` does.
  package func row(count: Int, keeping exists: (WindowID) -> Bool) -> WorkspaceRow {
    let workspaces = workspaces ?? []
    var row = WorkspaceRow(count: max(count, workspaces.count))
    for (index, saved) in workspaces.enumerated() where index < row.count {
      row[index] = saved.workspace(keeping: exists)
    }
    let currentIndex = currentIndex ?? 0
    row.select(currentIndex < row.count ? currentIndex : 0)
    row.setCount(count)
    return row
  }

  /// The rows as saved, holding only windows that still exist (`exists`). A version 1 file gives
  /// one row of `count` workspaces (see `row(count:keeping:)`) on a display not yet known, which
  /// the next sync puts on the primary display.
  package func rows(count: Int, keeping exists: (WindowID) -> Bool) -> DisplayRows {
    guard let displays else {
      let row = row(count: count, keeping: exists)
      return DisplayRows(
        entries: [DisplayRows.Entry(key: DisplayRows.unknownDisplay, row: row)],
        homes: Dictionary(uniqueKeysWithValues: row.numbers.map { ($0, .configured(1)) }),
        focusedKey: nil)
    }
    let entries = displays.map { saved in
      var row = WorkspaceRow(numbers: saved.numbers)
      for (index, workspace) in saved.workspaces.enumerated() where index < row.count {
        row[index] = workspace.workspace(keeping: exists)
      }
      row.select(saved.currentIndex < row.count ? saved.currentIndex : 0)
      return DisplayRows.Entry(key: saved.key, row: row)
    }
    let homes = Dictionary(
      (self.homes ?? []).map { ($0.number, $0.home) }, uniquingKeysWith: { first, _ in first })
    return DisplayRows(entries: entries, homes: homes, focusedKey: focusedDisplay)
  }

  // MARK: - File

  /// Writes the state to `path` (replacing any earlier file), creating the directory if needed.
  package func write(to path: String) throws(SavedStateError) {
    let url = URL(fileURLWithPath: path)
    do {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      try encoder.encode(self).write(to: url, options: .atomic)
    } catch {
      throw .unwritable(path: path, reason: error.localizedDescription)
    }
  }

  /// Reads the state at `path`: `nil` if there is no file, an error if it can't be used or was
  /// written more than `maximumAge` before `now`.
  package static func read(
    from path: String, now: Date = Date()
  ) throws(SavedStateError) -> SavedState? {
    guard FileManager.default.fileExists(atPath: path) else { return nil }
    let state: SavedState
    do {
      let data = try Data(contentsOf: URL(fileURLWithPath: path))
      state = try JSONDecoder().decode(SavedState.self, from: data)
    } catch {
      throw .unreadable(path: path, reason: error.localizedDescription)
    }
    guard readableVersions.contains(state.version) else {
      throw .unknownVersion(path: path, version: state.version)
    }
    if let writtenAt = state.writtenAt, now.timeIntervalSince(writtenAt) > maximumAge {
      throw .stale(path: path, writtenAt: writtenAt)
    }
    return state
  }
}

extension SavedState.SavedWorkspace {
  /// The workspace as saved, with only the windows that still exist (`exists`). A window that
  /// is gone leaves its layout states as a closed window does.
  func workspace(keeping exists: (WindowID) -> Bool) -> Workspace {
    var states = self.states
    var remaining = windows
    for windowID in windows where !exists(windowID) {
      states.remove(windowID, from: remaining)
      remaining.removeAll { $0 == windowID }
    }
    var workspace = Workspace(layout: layout, layoutStates: states)
    for windowID in remaining {
      workspace.insert(windowID)
    }
    if let focused { workspace.setFocus(focused) }
    if let firstVisible { workspace.scroll(toFirstVisible: firstVisible) }
    return workspace
  }
}
