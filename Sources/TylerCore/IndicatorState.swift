/// What the menu bar item shows: the workspace numbers with the current one in brackets, the
/// current workspace's layout, and a small menu, such as `1 [2] 3 4  ▥`. Built from the
/// manager's state; the platform layer only draws it.
public struct IndicatorState: Equatable, Sendable {
  /// One workspace as the indicator sees it.
  public struct Workspace: Equatable, Sendable {
    public var windowCount: Int
    public var layout: LayoutKind

    public init(windowCount: Int, layout: LayoutKind) {
      self.windowCount = windowCount
      self.layout = layout
    }
  }

  /// One piece of the menu bar title. Faint pieces (empty workspaces, notices) are drawn in a
  /// dimmer colour.
  public struct TitlePart: Equatable, Sendable {
    public var text: String
    public var isFaint: Bool

    public init(_ text: String, isFaint: Bool = false) {
      self.text = text
      self.isFaint = isFaint
    }
  }

  /// One entry of the menu. Choosing it sends `request` to the manager, as `tyler` would.
  public enum MenuItem: Equatable, Sendable {
    case action(title: String, isChecked: Bool, request: Request)
    /// Shown greyed out; choosing it does nothing.
    case note(String)
    case separator
  }

  public var workspaces: [Workspace]
  public var currentIndex: Int
  public var tiling: ServerStatus.Tiling

  public init(workspaces: [Workspace], currentIndex: Int, tiling: ServerStatus.Tiling) {
    self.workspaces = workspaces
    self.currentIndex = currentIndex
    self.tiling = tiling
  }

  public init(row: WorkspaceRow, tiling: ServerStatus.Tiling) {
    self.init(
      workspaces: row.workspaces.map { Workspace(windowCount: $0.count, layout: $0.layout) },
      currentIndex: row.currentIndex,
      tiling: tiling)
  }

  /// The menu bar title: every workspace's number, from left to right, with the current one
  /// in brackets and empty ones faint, then the layout's symbol (`▥` tall, `▢` full). Exactly one
  /// number is bracketed, so the title keeps its width while switching. Without tiling, windows
  /// don't belong to workspaces, and a faint notice stands in for all of it.
  public var title: [TitlePart] {
    if let notice { return [TitlePart("tyler: \(notice)", isFaint: true)] }
    var parts: [TitlePart] = []
    for index in workspaces.indices {
      if index > 0 { parts.append(TitlePart(" ")) }
      let number = String(index + 1)
      parts.append(
        index == currentIndex
          ? TitlePart("[\(number)]")
          : TitlePart(number, isFaint: workspaces[index].windowCount == 0))
    }
    if let layout { parts.append(TitlePart("  \(layout.symbol)")) }
    return parts
  }

  /// The current workspace's layout, or `nil` when tiling isn't running.
  public var layout: LayoutKind? {
    guard tiling == .on, workspaces.indices.contains(currentIndex) else { return nil }
    return workspaces[currentIndex].layout
  }

  /// Replaces the title when tiling isn't running.
  var notice: String? {
    switch tiling {
    case .on: nil
    case .off: "tiling off"
    case .waitingForPermission: "no access"
    }
  }

  public var menu: [MenuItem] {
    switch tiling {
    case .waitingForPermission:
      return [.note("Waiting for Accessibility permission")]
    case .off:
      return [.action(title: "Tiling: off", isChecked: false, request: .tiling(.on))]
    case .on:
      let workspaceItems = workspaces.indices.map { index -> MenuItem in
        .action(
          title: "Workspace \(index + 1)\(Self.countSuffix(workspaces[index].windowCount))",
          isChecked: index == currentIndex,
          request: .workspace(.number(index + 1)))
      }
      guard let layout else { return workspaceItems }
      return workspaceItems + [
        .separator,
        .action(
          title: "Layout: \(layout.rawValue) → \(layout.next.rawValue)", isChecked: false,
          request: .layout(.next)),
        .action(title: "Tiling: on", isChecked: true, request: .tiling(.off)),
      ]
    }
  }

  private static func countSuffix(_ count: Int) -> String {
    switch count {
    case 0: ""
    case 1: "  (1 window)"
    default: "  (\(count) windows)"
    }
  }
}
