import TylerCore

/// The menu every indicator opens: the workspaces, then the layout and tiling. Shared by the
/// text item and the map, so both offer the same.
struct IndicatorMenu: Equatable, Sendable {
  /// One entry of the menu. Choosing it sends `request` to the manager, as `tyler` would.
  enum Item: Equatable, Sendable {
    case action(title: String, isChecked: Bool, request: Request)
    /// Shown greyed out; choosing it does nothing.
    case note(String)
    case separator
  }

  let items: [Item]

  init(_ snapshot: IndicatorSnapshot) {
    switch snapshot.tiling {
    case .waitingForPermission:
      items = [.note("Waiting for Accessibility permission")]
    case .off:
      items = [.action(title: "Tiling: off", isChecked: false, request: .tiling(.on))]
    case .on:
      let row = snapshot.row
      let workspaceItems = row.indices.map { index -> Item in
        .action(
          title: "Workspace \(index + 1)\(Self.countSuffix(row[index].count))",
          isChecked: index == row.currentIndex,
          request: .workspace(.number(index + 1)))
      }
      let layout = row.current.layout
      items =
        workspaceItems + [
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
