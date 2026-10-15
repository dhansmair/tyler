import CoreGraphics

/// xmonad's "Tall": the first windows (the master section, one window unless promoted) are
/// stacked in the left column and the rest in the right column, with equal heights unless their
/// row weights say otherwise. Two windows sit side by side, three give one on the left and two
/// above each other on the right. With every window in the master section, there is one column.
package struct TallLayout: Layout {
  package init() {}

  package func frames(
    of windows: [WindowID], state: TallLayoutState, in area: CGRect, gaps: LayoutGaps
  ) -> [CGRect] {
    Self.columns(count: windows.count, state: state).frames(in: area, gaps: gaps)
  }

  /// Follows the divider between the master section and the stack, and the dividers between the
  /// windows of a column.
  package func state(
    after resize: ResizedWindow, of windows: [WindowID], state: TallLayoutState, in area: CGRect,
    gaps: LayoutGaps
  ) -> TallLayoutState? {
    let columns = Self.columns(count: windows.count, state: state)
    guard
      let weights = columns.resize(index: resize.index, to: resize.frame, in: area, gaps: gaps)
    else { return nil }
    var updated = state
    updated.weights = ColumnWeights(rows: weights.rows)
    if columns.rowCounts.count == 2 {
      let columns = weights.columns(count: 2)
      updated.setMainRatio(columns[0] / (columns[0] + columns[1]))
    }
    return updated == state ? nil : updated
  }

  /// One column for the master section and one for the rest, split by the master ratio.
  static func columns(count: Int, state: TallLayoutState) -> ColumnLayout {
    let rows = state.rowWeights
    let mains = state.mainCount(for: count)
    guard mains < count else {
      return ColumnLayout(rowCounts: [count], columnWeights: [1], rowWeights: rows)
    }
    let ratio = state.mainRatio
    return ColumnLayout(
      rowCounts: [mains, count - mains], columnWeights: [ratio, 1 - ratio], rowWeights: rows)
  }
}
