import CoreGraphics

/// niri's scrolling layout: the windows form one long row of columns without gaps, left to right
/// in list order, and the display shows a view of it, so a column can be partly in view. Columns
/// wholly out of view get frames off the area; the workspace parks them.
package struct StripLayout: ScrollingLayout {
  package typealias State = StripLayoutState

  package init() {}

  package func frames(
    of windows: [WindowID], state: StripLayoutState, startingAt view: Int, in area: CGRect,
    gaps: LayoutGaps
  ) -> [CGRect] {
    let columns = state.columns(of: windows)
    guard let start = columns.column(of: view) ?? columns.columns.indices.first
    else { return [] }
    let geometry = StripGeometry(area: area, gaps: gaps)
    var frames = Array(repeating: CGRect.zero, count: windows.count)
    for (column, members) in columns.columns.enumerated() {
      let position = columns.offset(of: column) - columns.offset(of: start)
      let halves = columns.widths[column]
      let left = geometry.left(ofColumnAt: position, halves: halves)
      let width = geometry.width(of: halves, at: position)
      let rows = members.count == 2 ? geometry.halfRows : [geometry.fullRow]
      for (member, row) in zip(members, rows) {
        frames[member] =
          IntegerBox(minX: left, minY: row.origin, width: width, height: row.length)
          .rect
      }
    }
    return frames
  }
}

extension StripLayout {
  package func restingViews(
    of windows: [WindowID], state: StripLayoutState, in area: CGRect, gaps: LayoutGaps
  ) -> [RestingView] {
    let columns = state.columns(of: windows)
    let geometry = StripGeometry(area: area, gaps: gaps)
    return columns.starts.map { start in
      RestingView(
        firstVisible: columns.columns[start][0],
        offset: CGFloat(geometry.left(at: columns.offset(of: start)) - geometry.left(at: 0)))
    }
  }

  package func fittedView(
    of windows: [WindowID], state: StripLayoutState, from view: Int, showing focused: Int?
  ) -> Int {
    let columns = state.columns(of: windows)
    guard !columns.columns.isEmpty else { return 0 }
    let start = columns.fittedStart(
      previous: columns.column(of: view) ?? 0,
      focused: focused.flatMap(columns.column(of:)))
    return columns.columns[start][0]
  }

  package func scrollTarget(
    startingAt index: Int, of windows: [WindowID], state: StripLayoutState, focused: Int?
  ) -> ScrollTarget? {
    let columns = state.columns(of: windows)
    guard let column = columns.column(of: index) else { return nil }
    let start = columns.clampedToEnd(column)
    let visible = columns.visible(from: start)
    guard let focusedColumn = focused.flatMap(columns.column(of:)),
      !visible.contains(focusedColumn)
    else { return ScrollTarget(firstVisible: columns.columns[start][0], focused: focused) }
    let nearest = focusedColumn < visible.lowerBound ? visible.lowerBound : visible.upperBound - 1
    return ScrollTarget(
      firstVisible: columns.columns[start][0], focused: columns.columns[nearest][0])
  }
}
