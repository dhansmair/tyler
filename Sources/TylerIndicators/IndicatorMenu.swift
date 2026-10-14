import TylerCore
import TylerProtocol

/// The menu every indicator opens: the workspaces, then the layout and tiling, then the config
/// and quitting. Shared by the text item and the map, so both offer the same.
struct IndicatorMenu: Equatable, Sendable {
  /// One entry of the menu. Choosing an action hands its `choice` to the indicator's `perform`.
  enum Item: Equatable, Sendable {
    case action(title: String, isChecked: Bool, choice: MenuChoice)
    /// Shown greyed out; choosing it does nothing.
    case note(String)
    case separator
  }

  let items: [Item]

  init(_ snapshot: IndicatorSnapshot) {
    items = Self.tilingItems(snapshot) + Self.tylerdItems
  }

  private static let tylerdItems: [Item] = [
    .separator,
    .action(title: "Reload config", isChecked: false, choice: .request(.reload)),
    .action(title: "Open config", isChecked: false, choice: .request(.configEdit)),
    .action(title: "Quit tyler", isChecked: false, choice: .quit),
  ]

  private static func tilingItems(_ snapshot: IndicatorSnapshot) -> [Item] {
    switch snapshot.tiling {
    case .waitingForPermission:
      return [.note("Waiting for Accessibility permission")]
    case .off:
      return [.action(title: "Tiling: off", isChecked: false, choice: .request(.tiling(.on)))]
    case .on:
      let row = snapshot.row
      let workspaceItems = row.indices.map { index -> Item in
        .action(
          title: "Workspace \(row.number(at: index))\(Self.countSuffix(row[index].count))",
          isChecked: index == row.currentIndex,
          choice: .request(.workspace(.number(row.number(at: index)))))
      }
      let layout = row.current.layout
      return workspaceItems + [
        .separator,
        .action(
          title: "Layout: \(layout.rawValue) → \(layout.next(in: snapshot.layoutCycle).rawValue)",
          isChecked: false,
          choice: .request(.layout(.next))),
        .action(title: "Tiling: on", isChecked: true, choice: .request(.tiling(.off))),
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
