import CoreGraphics

/// Columns of rows, two windows high: `tall` up to three windows, then the four corners, then
/// more columns, up to `maximumColumns`, after which the columns get a third row and so on.
/// When the windows don't fill every column, the first one holds what is left over, so an odd
/// count leaves the master alone in the first column, as in `tall`.
package struct GridLayout: Layout {
  /// The most columns a grid has: more would be too narrow for most apps on a laptop display.
  package static let maximumColumns = 4

  package init() {}

  package func frames(
    of windows: [WindowID], state: GridLayoutState, in area: CGRect, gaps: LayoutGaps
  ) -> [CGRect] {
    Self.columns(count: windows.count, state: state).frames(in: area, gaps: gaps)
  }

  /// Follows the dividers between columns and between the windows of a column.
  package func state(
    after resize: ResizedWindow, of windows: [WindowID], state: GridLayoutState, in area: CGRect,
    gaps: LayoutGaps
  ) -> GridLayoutState? {
    guard
      let weights = Self.columns(count: windows.count, state: state).resize(
        index: resize.index, to: resize.frame, in: area, gaps: gaps),
      weights != state.weights
    else { return nil }
    return GridLayoutState(weights: weights)
  }

  /// How many windows go in each column, left to right: 1 → `[1]`, 3 → `[1, 2]`, 5 →
  /// `[1, 2, 2]`, 9 → `[3, 3, 3]`.
  static func rowCounts(for count: Int) -> [Int] {
    guard count > 2 else { return Array(repeating: 1, count: max(count, 1)) }
    let rows = max(2, (count + maximumColumns - 1) / maximumColumns)
    let columns = (count + rows - 1) / rows
    return [count - rows * (columns - 1)] + Array(repeating: rows, count: columns - 1)
  }

  static func columns(count: Int, state: GridLayoutState) -> ColumnLayout {
    let rowCounts = count > 0 ? rowCounts(for: count) : [0]
    return ColumnLayout(rowCounts: rowCounts, weights: state.weights)
  }
}
