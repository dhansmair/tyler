import CoreGraphics

/// Works out which windows each workspace should hold, given the windows that exist. Pure: the
/// server applies the result to its workspaces and parks the arrivals.
///
/// A window stays on its workspace while it is tileable and not floated; parked and sliding
/// windows keep their place whatever their frame says. Windows on the current workspace leave it
/// when they move to another display. Tileable windows on the primary display that belong to no
/// workspace join the current one, unless they have never been tiled and their app is assigned
/// to another workspace: then they arrive there, to be parked.
public struct WorkspaceSync: Equatable, Sendable {
  /// Per workspace, the windows it should hold, as `Workspace.sync(eligible:)` takes them.
  public var eligible: [[WindowID]]
  /// Windows newly assigned to a workspace that isn't on screen.
  public var arrivals: [WindowID]

  /// What the manager knows about windows beyond their `WindowInfo`.
  public struct Marks: Sendable {
    /// Windows the user took out of tiling.
    public var floated: Set<WindowID>
    /// Windows that have been on a workspace; app assignments leave them alone.
    public var seen: Set<WindowID>
    /// Windows that are sliding or that a pan may move; they keep their place.
    public var sliding: Set<WindowID>

    public init(floated: Set<WindowID>, seen: Set<WindowID>, sliding: Set<WindowID>) {
      self.floated = floated
      self.seen = seen
      self.sliding = sliding
    }
  }

  /// `nil` while no display is connected: then nothing is decided, so parked windows aren't
  /// forgotten while they are still parked. `displays` lists the primary display first;
  /// `assignedWorkspace` gives the 1-based workspace the config assigns a window's app to.
  public static func plan(
    for stack: WorkspaceStack, windows: [WindowInfo], displays: [DisplayInfo], marks: Marks,
    assignedWorkspace: (WindowInfo) -> Int?
  ) -> WorkspaceSync? {
    guard let primary = displays.first else { return nil }
    let byID = Dictionary(windows.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
    let isOnPrimary = { (window: WindowInfo) in
      DisplayGeometry.display(containing: window.frame, in: displays)?.id == primary.id
    }
    let isCandidate = { (window: WindowInfo) in
      window.isTileable && !marks.floated.contains(window.id)
    }
    // Windows that have been tiled before, and apps without an assignment, go to the current
    // workspace (`nil`).
    let assignedIndex = { (window: WindowInfo) -> Int? in
      guard !marks.seen.contains(window.id), let number = assignedWorkspace(window),
        stack.indices.contains(number - 1), number - 1 != stack.currentIndex
      else { return nil }
      return number - 1
    }
    let assigned = stack.allWindows
    let newcomers = Dictionary(
      grouping: windows.filter { window in
        !assigned.contains(window.id) && isCandidate(window) && isOnPrimary(window)
      },
      by: assignedIndex)
    var sync = WorkspaceSync(eligible: [], arrivals: [])
    for index in stack.indices {
      let isCurrent = index == stack.currentIndex
      var eligible = stack[index].windows.filter { windowID in
        guard let window = byID[windowID], isCandidate(window) else { return false }
        return !isCurrent || marks.sliding.contains(windowID) || isOnPrimary(window)
      }
      var joining = newcomers[index] ?? []
      if isCurrent {
        joining += newcomers[nil] ?? []
        if stack[index].count == 0 {
          // First fill: left to right, then top to bottom, so the layout matches the screen.
          joining.sort { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
        }
      } else {
        sync.arrivals += joining.map(\.id)
      }
      eligible += joining.map(\.id)
      sync.eligible.append(eligible)
    }
    return sync
  }
}
