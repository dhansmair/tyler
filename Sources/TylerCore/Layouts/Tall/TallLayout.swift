import CoreGraphics

/// xmonad's "Tall": the first window (the master) fills the left column and the rest are
/// stacked in the right column, with equal heights unless their row weights say otherwise. Two
/// windows sit side by side, three give one on the left and two above each other on the right.
package struct TallLayout: Layout {
  package init() {}

  package func frames(
    of windows: [WindowID], state: TallLayoutState, in area: CGRect, gaps: LayoutGaps
  ) -> [CGRect] {
    Self.columns(count: windows.count, state: state).frames(in: area, gaps: gaps)
  }

  /// Follows the divider between the master and the stack, and the dividers between stacked
  /// windows.
  package func state(
    after resize: ResizedWindow, of windows: [WindowID], state: TallLayoutState, in area: CGRect,
    gaps: LayoutGaps
  ) -> TallLayoutState? {
    guard
      let weights = Self.columns(count: windows.count, state: state).resize(
        index: resize.index, to: resize.frame, in: area, gaps: gaps)
    else { return nil }
    var updated = state
    updated.weights = ColumnWeights(rows: weights.rows)
    if windows.count > 1 {
      let columns = weights.columns(count: 2)
      updated.setMainRatio(columns[0] / (columns[0] + columns[1]))
    }
    return updated == state ? nil : updated
  }

  /// One column for the master and one for the rest, split by the master ratio.
  static func columns(count: Int, state: TallLayoutState) -> ColumnLayout {
    let rows = state.rowWeights
    guard count > 1 else {
      return ColumnLayout(rowCounts: [count], columnWeights: [1], rowWeights: rows)
    }
    let ratio = state.mainRatio
    return ColumnLayout(
      rowCounts: [1, count - 1], columnWeights: [ratio, 1 - ratio], rowWeights: rows)
  }
}
