/// The layouts a workspace can use. `next` cycles through them in declaration order.
package enum LayoutKind: String, Codable, CaseIterable, Sendable {
  case tall
  case grid
  case full
  case strip

  /// The layouts `layout next` goes through unless the config says otherwise. The strip is
  /// left out while it is experimental.
  package static let defaultCycle: [LayoutKind] = [.tall, .grid, .full]

  /// The layout after this one in `cycle`, wrapping around; the first of `cycle` when this one
  /// isn't in it (it was chosen by name), and this one when `cycle` is empty.
  package func next(in cycle: [LayoutKind]) -> LayoutKind {
    guard let index = cycle.firstIndex(of: self) else { return cycle.first ?? self }
    return cycle[(index + 1) % cycle.count]
  }

  /// The layout, bound to its field of `LayoutStates`.
  var bound: any BoundLayout {
    switch self {
    case .tall: Bound(layout: TallLayout(), state: \.tall)
    case .grid: Bound(layout: GridLayout(), state: \.grid)
    case .full: Bound(layout: FullLayout(), state: \.full)
    case .strip: BoundScrolling(layout: StripLayout(), state: \.strip)
    }
  }

  /// How the menu bar item shows this layout.
  package var symbol: String {
    switch self {
    case .tall: "▥"
    case .grid: "▦"
    case .full: "▢"
    case .strip: "↔"
    }
  }
}
