import CoreGraphics
import Foundation

/// The workspaces as tylerd leaves them when it restarts, so the next tylerd can carry on where
/// it stopped instead of tiling everything onto the first workspace. Windows are identified by
/// their `WindowID`, which stays the same while the window lives.
public struct SavedState: Codable, Equatable, Sendable {
  /// Bumped whenever the format changes; a file with another version is ignored.
  public static let currentVersion = 1

  public struct SavedWorkspace: Codable, Equatable, Sendable {
    public var windows: [WindowID]
    public var focused: WindowID?
    public var layout: LayoutKind
    public var mainRatio: Double
    /// `LayoutParameters.rowWeights`; missing in files from before mouse resizing.
    public var rowWeights: [[Double]]?

    public init(
      windows: [WindowID], focused: WindowID?, layout: LayoutKind, mainRatio: Double,
      rowWeights: [[Double]]? = nil
    ) {
      self.windows = windows
      self.focused = focused
      self.layout = layout
      self.mainRatio = mainRatio
      self.rowWeights = rowWeights
    }
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
  public var workspaces: [SavedWorkspace]
  /// 0-based, like `WorkspaceStack.currentIndex`.
  public var currentIndex: Int
  public var floated: [WindowID]
  public var tilingEnabled: Bool
  public var originalFrames: [OriginalFrame]
  /// Windows that have been tiled, so app assignments leave them alone; missing in files from
  /// before app assignments.
  public var seen: [WindowID]?

  public init(
    stack: WorkspaceStack, floated: Set<WindowID>, tilingEnabled: Bool,
    originalFrames: [WindowID: CGRect], seen: Set<WindowID> = []
  ) {
    version = Self.currentVersion
    workspaces = stack.workspaces.map { workspace in
      SavedWorkspace(
        windows: workspace.windows, focused: workspace.focused, layout: workspace.layout,
        mainRatio: workspace.parameters.mainRatio, rowWeights: workspace.parameters.rowWeights)
    }
    currentIndex = stack.currentIndex
    self.floated = floated.sorted()
    self.tilingEnabled = tilingEnabled
    self.originalFrames = originalFrames.keys.sorted().compactMap { windowID in
      originalFrames[windowID].map { OriginalFrame(id: windowID, frame: $0) }
    }
    self.seen = seen.sorted()
  }

  /// The windows the previous tylerd had tiled. A file from before app assignments doesn't
  /// list them, so every window it mentions counts.
  public var seenWindows: Set<WindowID> {
    if let seen { return Set(seen) }
    return Set(workspaces.flatMap(\.windows) + floated)
  }

  /// A stack of `count` workspaces holding the saved windows that still exist (`exists`), in
  /// their saved order, with their focus, layout, ratio and row weights. Saved workspaces beyond
  /// `count` are merged into the last one, as `WorkspaceStack.setCount` does.
  public func stack(count: Int, keeping exists: (WindowID) -> Bool) -> WorkspaceStack {
    var stack = WorkspaceStack(count: max(count, workspaces.count))
    for (index, saved) in workspaces.enumerated() where index < stack.count {
      let parameters = LayoutParameters(
        mainRatio: saved.mainRatio, rowWeights: saved.rowWeights ?? [])
      var workspace = Workspace(layout: saved.layout, parameters: parameters)
      for windowID in saved.windows where exists(windowID) {
        workspace.insert(windowID)
      }
      if let focused = saved.focused { workspace.setFocus(focused) }
      stack[index] = workspace
    }
    stack.select(currentIndex < stack.count ? currentIndex : 0)
    stack.setCount(count)
    return stack
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
    guard state.version == currentVersion else {
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
      "\(path) has format version \(version), but this tylerd reads version "
        + "\(SavedState.currentVersion)"
    }
  }
}
