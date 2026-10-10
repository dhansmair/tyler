import CoreGraphics

/// xmonad's "Tall": the first window (the master) fills the left column and the rest are
/// stacked in the right column, with equal heights unless their row weights say otherwise. Two
/// windows sit side by side, three give one on the left and two above each other on the right.
public struct TallLayout: Layout {
  public init() {}

  public func frames(count: Int, in area: CGRect, parameters: LayoutParameters) -> [CGRect] {
    Self.columns(count: count, parameters: parameters).frames(in: area, parameters: parameters)
  }

  /// One column for the master and one for the rest, split by the master ratio.
  static func columns(count: Int, parameters: LayoutParameters) -> ColumnLayout {
    guard count > 1 else { return ColumnLayout(rowCounts: [count], columnWeights: [1]) }
    return ColumnLayout(
      rowCounts: [1, count - 1],
      columnWeights: [parameters.mainRatio, 1 - parameters.mainRatio])
  }
}

/// Every window gets the whole area. The focused window is the one you see, because focusing
/// raises it.
public struct FullLayout: Layout {
  public init() {}

  public func frames(count: Int, in area: CGRect, parameters: LayoutParameters) -> [CGRect] {
    guard count > 0 else { return [] }
    let box = IntegerBox(area, inset: parameters.outerGap)
    return Array(repeating: box.rect, count: count)
  }
}

/// Windows in columns, left to right, each column a stack of rows, top to bottom. The list
/// fills the first column from the top, then the next. Layouts that are columns of rows
/// (`tall`, and later `grid`) only say how many windows go in each column and how wide the
/// columns are; the frames, and row heights from `LayoutParameters.rowWeights`, are worked out
/// here once.
struct ColumnLayout: Equatable {
  /// Windows per column, left to right.
  let rowCounts: [Int]
  /// Relative widths, one per column.
  let columnWeights: [Double]

  /// One frame per window, in list order, in whole points.
  func frames(in area: CGRect, parameters: LayoutParameters) -> [CGRect] {
    guard rowCounts.contains(where: { $0 > 0 }) else { return [] }
    let box = IntegerBox(area, inset: parameters.outerGap)
    let gap = Int(parameters.innerGap.rounded())
    let columns = IntegerBox.split(
      origin: box.minX, length: box.width, weights: columnWeights, gap: gap)
    var frames: [CGRect] = []
    for (index, (rowCount, column)) in zip(rowCounts, columns).enumerated() {
      let rows = IntegerBox.split(
        origin: box.minY, length: box.height,
        weights: parameters.rowWeights(inColumn: index, count: rowCount), gap: gap)
      frames += rows.map { row in
        IntegerBox(minX: column.origin, minY: row.origin, width: column.length, height: row.length)
          .rect
      }
    }
    return frames
  }
}
