import CoreGraphics

/// xmonad's "Tall": the first window (the master) fills the left column and the rest are
/// stacked in the right column, with equal heights unless their row weights say otherwise. Two
/// windows sit side by side, three give one on the left and two above each other on the right.
public struct TallLayout: Layout {
  public init() {}

  public func frames(for input: LayoutInput, in area: CGRect, gaps: LayoutGaps) -> [CGRect] {
    Self.columns(for: input).frames(in: area, parameters: input.parameters, gaps: gaps)
  }

  /// Follows the divider between the master and the stack, and the dividers between stacked
  /// windows.
  public func parameters(
    afterResizing index: Int,
    to frame: CGRect,
    input: LayoutInput,
    in area: CGRect,
    gaps: LayoutGaps
  ) -> LayoutParameters? {
    let parameters = input.parameters
    guard
      let resize = Self.columns(for: input).resize(
        index: index, to: frame, in: area, parameters: parameters, gaps: gaps)
    else { return nil }
    var updated = resize.parameters
    if let widths = resize.columnWidths, widths.count == 2, widths[0] + widths[1] > 0 {
      updated.setMainRatio(Double(widths[0]) / Double(widths[0] + widths[1]))
    }
    return updated == parameters ? nil : updated
  }

  /// One column for the master and one for the rest, split by the master ratio.
  static func columns(for input: LayoutInput) -> ColumnLayout {
    let count = input.count
    guard count > 1 else { return ColumnLayout(rowCounts: [count], columnWeights: [1]) }
    let ratio = input.parameters.mainRatio
    return ColumnLayout(rowCounts: [1, count - 1], columnWeights: [ratio, 1 - ratio])
  }
}

/// Every window gets the whole area. The focused window is the one you see, because focusing
/// raises it.
public struct FullLayout: Layout {
  public init() {}

  public func frames(for input: LayoutInput, in area: CGRect, gaps: LayoutGaps) -> [CGRect] {
    guard input.count > 0 else { return [] }
    let box = IntegerBox(area, inset: gaps.outer)
    return Array(repeating: box.rect, count: input.count)
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

  /// The least share of two neighbours' combined width or height that a divider drag leaves
  /// to either of them, like `LayoutParameters.ratioRange` does for the master.
  static let minimumShare = LayoutParameters.ratioRange.lowerBound

  /// What dragging the edges of a window changes. Column widths are in points and not stored
  /// here: each layout keeps its own column parameters (tall: the master ratio).
  struct Resize: Equatable {
    var columnWidths: [Int]?
    var parameters: LayoutParameters
  }

  /// One frame per window, in list order, in whole points.
  func frames(in area: CGRect, parameters: LayoutParameters, gaps: LayoutGaps) -> [CGRect] {
    guard rowCounts.contains(where: { $0 > 0 }) else { return [] }
    let box = IntegerBox(area, inset: gaps.outer)
    let gap = Int(gaps.inner.rounded())
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

  /// How the dividers move when window `index` is resized to `frame`: a moved left or right edge
  /// moves the divider between two columns, a moved top or bottom edge the divider between two
  /// rows of its column. An edge only counts if the opposite edge stayed put (otherwise the
  /// window moved rather than resized). Returns `nil` when no divider moved.
  func resize(
    index: Int,
    to frame: CGRect,
    in area: CGRect,
    parameters: LayoutParameters,
    gaps: LayoutGaps
  ) -> Resize? {
    let current = frames(in: area, parameters: parameters, gaps: gaps)
    guard current.indices.contains(index), let (column, row) = position(of: index) else {
      return nil
    }
    let old = current[index]
    var result = Resize(columnWidths: nil, parameters: parameters)

    let columnFirsts = rowCounts.indices.map { rowCounts[..<$0].reduce(0, +) }
    let widths = columnFirsts.enumerated().map { column, first in
      rowCounts[column] > 0 ? Int(current[first].width) : 0
    }
    let columnDrag = Self.divider(
      from: (old.minX, old.maxX), to: (frame.minX, frame.maxX), part: column,
      of: rowCounts.count)
    if let (pair, delta) = columnDrag {
      result.columnWidths = Self.moving(pair, by: delta, in: widths)
    }

    let rowFrames = current[columnFirsts[column]..<(columnFirsts[column] + rowCounts[column])]
    let heights = rowFrames.map { Int($0.height) }
    let rowDrag = Self.divider(
      from: (old.minY, old.maxY), to: (frame.minY, frame.maxY), part: row, of: heights.count)
    if let (pair, delta) = rowDrag {
      let moved = Self.moving(pair, by: delta, in: heights)
      var weights = parameters.rowWeights(inColumn: column, count: heights.count)
      let total = weights[pair] + weights[pair + 1]
      let combined = Double(moved[pair] + moved[pair + 1])
      if combined > 0 {
        weights[pair] = total * Double(moved[pair]) / combined
        weights[pair + 1] = total - weights[pair]
        result.parameters.setRowWeights(weights, inColumn: column)
      }
    }

    guard result.columnWidths != nil || result.parameters != parameters else { return nil }
    return result
  }

  /// The column and row of window `index`.
  private func position(of index: Int) -> (column: Int, row: Int)? {
    var first = 0
    for (column, count) in rowCounts.enumerated() {
      if index < first + count { return (column, index - first) }
      first += count
    }
    return nil
  }

  /// Which divider an edge drag moved and by how much. `old` and `new` are the leading and
  /// trailing edges of `part` (one of `count`) before and after. The divider before the part
  /// moved if its leading edge did, the one after it if its trailing edge did; it is returned as
  /// the index of the part before the divider. Edges within a point of where they were count as
  /// unmoved.
  private static func divider(
    from old: (leading: CGFloat, trailing: CGFloat),
    to new: (leading: CGFloat, trailing: CGFloat),
    part: Int,
    of count: Int
  ) -> (pair: Int, delta: Int)? {
    let leading = Int((new.leading - old.leading).rounded())
    let trailing = Int((new.trailing - old.trailing).rounded())
    let leadingMoved = abs(leading) > 1
    let trailingMoved = abs(trailing) > 1
    if leadingMoved && !trailingMoved && part > 0 { return (part - 1, leading) }
    if trailingMoved && !leadingMoved && part < count - 1 { return (part, trailing) }
    return nil
  }

  /// `sizes` with the divider after part `pair` moved by `delta`, keeping each of the two parts
  /// at least `minimumShare` of their combined size.
  private static func moving(_ pair: Int, by delta: Int, in sizes: [Int]) -> [Int] {
    let combined = sizes[pair] + sizes[pair + 1]
    let least = Int((Double(combined) * minimumShare).rounded())
    let first = min(max(sizes[pair] + delta, least), combined - least)
    var moved = sizes
    moved[pair] = first
    moved[pair + 1] = combined - first
    return moved
  }
}
