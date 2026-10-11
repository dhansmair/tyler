import CoreGraphics
import Foundation

/// The workspaces as tylerd leaves them when it restarts, so the next tylerd can carry on where
/// it stopped instead of tiling everything onto the first workspace. Windows are identified by
/// their `WindowID`, which stays the same while the window lives.
public struct SavedState: Codable, Equatable, Sendable {
  /// Bumped whenever the format changes; a file with another version is ignored.
  /// Version 2 holds a row per display; version 1, with a single row, is still read.
  public static let currentVersion = 2
  /// The versions `read` accepts.
  public static let readableVersions = 1...2

  public struct SavedWorkspace: Codable, Equatable, Sendable {
    public var windows: [WindowID]
    public var focused: WindowID?
    public var layout: LayoutKind
    public var mainRatio: Double
    /// `LayoutParameters.rowWeights`; missing in files from before mouse resizing.
    public var rowWeights: [[Double]]?
    /// The windows' strip sizes, other than `half`; missing in files from before the strip.
    public var sizes: [SavedSize]?
    /// `Workspace.firstVisible`; missing in files from before the strip.
    public var firstVisible: WindowID?

    public init(
      windows: [WindowID], focused: WindowID?, layout: LayoutKind, mainRatio: Double,
      rowWeights: [[Double]]? = nil, sizes: [SavedSize]? = nil, firstVisible: WindowID? = nil
    ) {
      self.windows = windows
      self.focused = focused
      self.layout = layout
      self.mainRatio = mainRatio
      self.rowWeights = rowWeights
      self.sizes = sizes
      self.firstVisible = firstVisible
    }
  }

  /// A window's size in the strip layout.
  public struct SavedSize: Codable, Equatable, Sendable {
    public var id: WindowID
    public var size: WindowSize

    public init(id: WindowID, size: WindowSize) {
      self.id = id
      self.size = size
    }
  }

  /// One display's row: the display, its workspaces with their numbers, and the one on screen.
  public struct SavedDisplay: Codable, Equatable, Sendable {
    public var key: DisplayKey
    public var numbers: [Int]
    public var workspaces: [SavedWorkspace]
    public var currentIndex: Int

    public init(_ entry: DisplayRows.Entry) {
      key = entry.key
      numbers = entry.row.numbers
      workspaces = entry.row.workspaces.map(SavedWorkspace.init)
      currentIndex = entry.row.currentIndex
    }
  }

  /// Where a workspace belongs when its display is connected.
  public struct SavedHome: Codable, Equatable, Sendable {
    public var number: Int
    public var home: WorkspaceHome
  }

  /// Where a window was before tylerd first moved it.
  public struct OriginalFrame: Codable, Equatable, Sendable {
    public var id: WindowID
    public var frame: CGRect

    public init(id: WindowID, frame: CGRect) {
      self.id = id
      self.frame = frame
    }
  }

  public var version: Int
  /// Each display's row (version 2).
  public var displays: [SavedDisplay]?
  /// Each workspace's home (version 2).
  public var homes: [SavedHome]?
  /// The display commands acted on (version 2).
  public var focusedDisplay: DisplayKey?
  /// The single row of version 1.
  public var workspaces: [SavedWorkspace]?
  /// 0-based, like `WorkspaceRow.currentIndex` (version 1).
  public var currentIndex: Int?
  public var floated: [WindowID]
  public var tilingEnabled: Bool
  public var originalFrames: [OriginalFrame]
  /// Windows that have been tiled, so app assignments leave them alone; missing in files from
  /// before app assignments.
  public var seen: [WindowID]?

  public init(
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
  public init(
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
  public var seenWindows: Set<WindowID> {
    if let seen { return Set(seen) }
    let saved = (workspaces ?? []) + (displays ?? []).flatMap(\.workspaces)
    return Set(saved.flatMap(\.windows) + floated)
  }

  /// A row of `count` workspaces holding the saved windows of a version 1 file that still exist
  /// (`exists`), in their saved order, with their focus, layout, ratio, row weights, strip sizes
  /// and view. Saved workspaces beyond `count` are merged into the last one, as
  /// `WorkspaceRow.setCount` does.
  public func row(count: Int, keeping exists: (WindowID) -> Bool) -> WorkspaceRow {
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
  public func rows(count: Int, keeping exists: (WindowID) -> Bool) -> DisplayRows {
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
  public func write(to path: String) throws(SavedStateError) {
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

  /// Reads the state at `path`: `nil` if there is no file, an error if it can't be used.
  public static func read(from path: String) throws(SavedStateError) -> SavedState? {
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
    return state
  }
}

public enum SavedStateError: Error, Equatable, Sendable, CustomStringConvertible {
  case unwritable(path: String, reason: String)
  case unreadable(path: String, reason: String)
  case unknownVersion(path: String, version: Int)

  public var description: String {
    switch self {
    case .unwritable(let path, let reason): "cannot write \(path): \(reason)"
    case .unreadable(let path, let reason): "cannot read \(path): \(reason)"
    case .unknownVersion(let path, let version):
      "\(path) has format version \(version), but this tylerd reads versions "
        + "\(SavedState.readableVersions.lowerBound) to \(SavedState.readableVersions.upperBound)"
    }
  }
}

extension SavedState.SavedWorkspace {
  init(_ workspace: Workspace) {
    self.init(
      windows: workspace.windows, focused: workspace.focused, layout: workspace.layout,
      mainRatio: workspace.parameters.mainRatio, rowWeights: workspace.parameters.rowWeights,
      sizes: workspace.sizes.sorted { $0.key < $1.key }.map {
        SavedState.SavedSize(id: $0.key, size: $0.value)
      },
      firstVisible: workspace.firstVisible)
  }

  /// The workspace as saved, with only the windows that still exist (`exists`).
  func workspace(keeping exists: (WindowID) -> Bool) -> Workspace {
    let parameters = LayoutParameters(mainRatio: mainRatio, rowWeights: rowWeights ?? [])
    var workspace = Workspace(layout: layout, parameters: parameters)
    for windowID in windows where exists(windowID) {
      workspace.insert(windowID)
    }
    for saved in sizes ?? [] {
      workspace.setSize(saved.size, of: saved.id)
    }
    if let focused { workspace.setFocus(focused) }
    if let firstVisible { workspace.scroll(toFirstVisible: firstVisible) }
    return workspace
  }
}
