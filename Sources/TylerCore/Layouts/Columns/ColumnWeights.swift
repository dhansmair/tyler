/// The relative sizes of a column layout's slots: `columns[c]` is the width of column `c`, and
/// `rows[c][r]` the height of row `r` of column `c`. Slots without an entry weigh 1, so the
/// default is equal sizes. Weights belong to the slot, not the window: a window moving into a
/// slot takes its size, and the weights of slots that empty are kept for when they fill again.
package struct ColumnWeights: Equatable, Sendable {
  package private(set) var columns: [Double]
  package private(set) var rows: [[Double]]

  package init(columns: [Double] = [], rows: [[Double]] = []) {
    self.columns = columns.map(Self.sanitize)
    self.rows = rows.map { column in column.map(Self.sanitize) }
  }

  /// The weights of the first `count` columns, with 1 for columns that have none.
  package func columns(count: Int) -> [Double] {
    Self.padded(columns, count: count)
  }

  /// The weights of the first `count` rows of `column`, with 1 for rows that have none.
  package func rows(inColumn column: Int, count: Int) -> [Double] {
    Self.padded(column < rows.count ? rows[column] : [], count: count)
  }

  /// Replaces the weights of the first `weights.count` columns, keeping the ones further right.
  package mutating func setColumns(_ weights: [Double]) {
    columns = Self.replacing(columns, with: weights)
  }

  /// Replaces the weights of the first `weights.count` rows of `column`, keeping the ones
  /// further down.
  package mutating func setRows(_ weights: [Double], inColumn column: Int) {
    while rows.count <= column { rows.append([]) }
    rows[column] = Self.replacing(rows[column], with: weights)
  }

  private static func padded(_ stored: [Double], count: Int) -> [Double] {
    (0..<count).map { index in index < stored.count ? stored[index] : 1 }
  }

  private static func replacing(_ stored: [Double], with weights: [Double]) -> [Double] {
    let sanitized = weights.map(sanitize)
    return sanitized + stored.dropFirst(sanitized.count)
  }

  /// A weight that can't share out space (zero, negative, infinite, NaN) counts as 1.
  private static func sanitize(_ weight: Double) -> Double {
    weight.isFinite && weight > 0 ? weight : 1
  }
}

extension ColumnWeights: Codable {
  private enum CodingKeys: String, CodingKey {
    case columns
    case rows
  }

  /// Decoded through `init(columns:rows:)`, so weights from a file are sanitised too.
  package init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      columns: try container.decode([Double].self, forKey: .columns),
      rows: try container.decode([[Double]].self, forKey: .rows))
  }
}
