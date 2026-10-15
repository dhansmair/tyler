import CoreGraphics

/// The ratio is clamped to `ratioRange` so neither column can vanish.
package struct TallLayoutState: LayoutState {
  package static let ratioRange: ClosedRange<Double> = 0.1...0.9

  package private(set) var mainRatio: Double
  /// How many windows, from the start of the list, the master section holds. Kept as the user
  /// set it; `mainCount(for:)` fits it to the windows there are.
  package private(set) var mainCount: Int
  /// Only the rows are used: `mainRatio` sets the column widths.
  var weights: ColumnWeights

  /// `rowWeights[column][row]`; missing rows weigh 1.
  package var rowWeights: [[Double]] { weights.rows }

  package init() {
    self.init(mainRatio: 0.5)
  }

  package init(mainRatio: Double = 0.5, rowWeights: [[Double]] = [], mainCount: Int = 1) {
    self.mainRatio = Self.clamp(mainRatio)
    self.weights = ColumnWeights(rows: rowWeights)
    self.mainCount = max(mainCount, 1)
  }

  /// The master section of a list of `count` windows: at least the first window, at most all.
  package func mainCount(for count: Int) -> Int {
    min(mainCount, count)
  }

  /// The master section takes one more window, the one that was first in the stack.
  mutating func growMainSection(of count: Int) {
    mainCount = mainCount(for: count) + 1
  }

  /// The master section gives its last window to the stack. It keeps at least one.
  mutating func shrinkMainSection(of count: Int) {
    mainCount = max(mainCount(for: count) - 1, 1)
  }

  /// A master that closes takes its place in the master section with it.
  package mutating func remove(_ windowID: WindowID, from windows: [WindowID]) {
    guard let index = windows.firstIndex(of: windowID), index < mainCount(for: windows.count)
    else { return }
    shrinkMainSection(of: windows.count)
  }

  /// Returns whether the ratio changed.
  @discardableResult
  package mutating func adjustRatio(by delta: Double) -> Bool {
    let updated = Self.clamp(mainRatio + delta)
    guard updated != mainRatio else { return false }
    mainRatio = updated
    return true
  }

  @discardableResult
  package mutating func setMainRatio(_ ratio: Double) -> Bool {
    adjustRatio(by: ratio - mainRatio)
  }

  /// Keeps the weights of the rows past `weights.count`, for when those rows fill again.
  package mutating func setRowWeights(_ weights: [Double], inColumn column: Int) {
    self.weights.setRows(weights, inColumn: column)
  }

  /// Missing rows weigh 1.
  package func rowWeights(inColumn column: Int, count: Int) -> [Double] {
    weights.rows(inColumn: column, count: count)
  }

  private static func clamp(_ ratio: Double) -> Double {
    // Rounded to three places so repeated +0.05 / -0.05 steps don't accumulate float noise.
    let rounded = (ratio * 1000).rounded() / 1000
    return rounded.clamped(to: ratioRange)
  }
}

extension TallLayoutState: Codable {
  private enum CodingKeys: String, CodingKey {
    case mainRatio
    case rowWeights
    case mainCount
  }

  /// Decoded through `init(mainRatio:rowWeights:mainCount:)`, so a ratio from a file is clamped
  /// too.
  package init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      mainRatio: try container.decode(Double.self, forKey: .mainRatio),
      rowWeights: try container.decodeIfPresent([[Double]].self, forKey: .rowWeights) ?? [],
      mainCount: try container.decodeIfPresent(Int.self, forKey: .mainCount) ?? 1)
  }

  package func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(mainRatio, forKey: .mainRatio)
    try container.encode(rowWeights, forKey: .rowWeights)
    try container.encode(mainCount, forKey: .mainCount)
  }
}
