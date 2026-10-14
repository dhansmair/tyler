import CoreGraphics

/// Windows in columns, left to right, each column a stack of rows, top to bottom. The list
/// fills the first column from the top, then the next. Layouts that are columns of rows
/// (`tall`, and later `grid`) only say how many windows go in each column and how big the slots
/// are; the frames, and the weights after a mouse resize, are worked out here once.
struct ColumnLayout: Equatable {
  /// Windows per column, left to right.
  let rowCounts: [Int]
  /// The relative sizes of the columns and of the rows in each column.
  let weights: ColumnWeights

  /// The least share of two neighbours' combined width or height that a divider drag leaves
  /// to either of them, like `TallLayoutState.ratioRange` does for the master.
  static let minimumShare = TallLayoutState.ratioRange.lowerBound

  init(rowCounts: [Int], weights: ColumnWeights) {
    self.rowCounts = rowCounts
    self.weights = weights
  }

  init(rowCounts: [Int], columnWeights: [Double], rowWeights: [[Double]] = []) {
    self.init(
      rowCounts: rowCounts, weights: ColumnWeights(columns: columnWeights, rows: rowWeights))
  }

  /// One frame per window, in list order, in whole points.
  func frames(in area: CGRect, gaps: LayoutGaps) -> [CGRect] {
    guard rowCounts.contains(where: { $0 > 0 }) else { return [] }
    let box = IntegerBox(area, inset: gaps.outer)
    let gap = Int(gaps.inner.rounded())
    let columns = IntegerBox.split(
      origin: box.minX, length: box.width, weights: weights.columns(count: rowCounts.count),
      gap: gap)
    var frames: [CGRect] = []
    for (index, (rowCount, column)) in zip(rowCounts, columns).enumerated() {
      let rows = IntegerBox.split(
        origin: box.minY, length: box.height,
        weights: weights.rows(inColumn: index, count: rowCount), gap: gap)
      frames += rows.map { row in
        IntegerBox(minX: column.origin, minY: row.origin, width: column.length, height: row.length)
          .rect
      }
    }
    return frames
  }

  /// The weights after window `index` is resized to `frame`: a moved left or right edge moves
  /// the divider between two columns, a moved top or bottom edge the divider between two rows of
  /// its column. An edge only counts if the opposite edge stayed put (otherwise the window moved
  /// rather than resized). Returns `nil` when no divider moved.
  func resize(index: Int, to frame: CGRect, in area: CGRect, gaps: LayoutGaps) -> ColumnWeights? {
    let current = frames(in: area, gaps: gaps)
    guard current.indices.contains(index), let (column, row) = position(of: index) else {
      return nil
    }
    let old = current[index]
    var updated = weights
    var didMove = false

    let columnFirsts = rowCounts.indices.map { rowCounts[..<$0].reduce(0, +) }
    let widths = columnFirsts.enumerated().map { column, first in
      rowCounts[column] > 0 ? Int(current[first].width) : 0
    }
    let columnDrag = Self.divider(
      from: (old.minX, old.maxX), to: (frame.minX, frame.maxX), part: column,
      of: rowCounts.count)
    if let (pair, delta) = columnDrag {
      let moved = Self.moving(pair, by: delta, in: widths)
      updated.setColumns(
        Self.sharing(pair, of: weights.columns(count: widths.count), like: moved))
      didMove = true
    }

    let rowFrames = current[columnFirsts[column]..<(columnFirsts[column] + rowCounts[column])]
    let heights = rowFrames.map { Int($0.height) }
    let rowDrag = Self.divider(
      from: (old.minY, old.maxY), to: (frame.minY, frame.maxY), part: row, of: heights.count)
    if let (pair, delta) = rowDrag {
      let moved = Self.moving(pair, by: delta, in: heights)
      let rows = weights.rows(inColumn: column, count: heights.count)
      updated.setRows(Self.sharing(pair, of: rows, like: moved), inColumn: column)
      didMove = true
    }

    return didMove ? updated : nil
  }

  /// `weights` with the two at `pair` and `pair + 1` sharing their total in the proportion of
  /// `sizes` at the same places.
  private static func sharing(_ pair: Int, of weights: [Double], like sizes: [Int]) -> [Double] {
    let combined = Double(sizes[pair] + sizes[pair + 1])
    guard combined > 0 else { return weights }
    let total = weights[pair] + weights[pair + 1]
    var shared = weights
    shared[pair] = total * Double(sizes[pair]) / combined
    shared[pair + 1] = total - shared[pair]
    return shared
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
