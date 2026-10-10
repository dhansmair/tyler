import CoreGraphics

/// Tunable inputs to every layout. Gaps are in points; the master ratio is clamped to
/// `ratioRange` so neither column of a tall layout can vanish.
public struct LayoutParameters: Equatable, Sendable {
  public static let ratioRange: ClosedRange<Double> = 0.1...0.9

  public private(set) var mainRatio: Double
  /// The relative heights of the rows in each column of a column layout: `rowWeights[c][r]` is
  /// row `r` of column `c`. Rows without an entry weigh 1, so the default is equal heights.
  /// Weights belong to the slot, not the window: a window moving into a row takes its height.
  public private(set) var rowWeights: [[Double]]
  /// Space between the layout area's edge and the windows.
  public let outerGap: CGFloat
  /// Space between neighbouring windows.
  public let innerGap: CGFloat

  public init(
    mainRatio: Double = 0.5,
    rowWeights: [[Double]] = [],
    outerGap: CGFloat = 0,
    innerGap: CGFloat = 0
  ) {
    self.mainRatio = Self.clamp(mainRatio)
    self.rowWeights = rowWeights.map { column in column.map(Self.sanitize) }
    self.outerGap = max(0, outerGap)
    self.innerGap = max(0, innerGap)
  }

  /// The same parameters with different gaps; the ratio and row weights are kept.
  public func withGaps(inner: CGFloat, outer: CGFloat) -> LayoutParameters {
    LayoutParameters(
      mainRatio: mainRatio, rowWeights: rowWeights, outerGap: outer, innerGap: inner)
  }

  /// Moves the ratio by `delta`, staying inside `ratioRange`. Returns whether it changed.
  @discardableResult
  public mutating func adjustRatio(by delta: Double) -> Bool {
    let updated = Self.clamp(mainRatio + delta)
    guard updated != mainRatio else { return false }
    mainRatio = updated
    return true
  }

  /// Sets the ratio, staying inside `ratioRange`. Returns whether it changed.
  @discardableResult
  public mutating func setMainRatio(_ ratio: Double) -> Bool {
    adjustRatio(by: ratio - mainRatio)
  }

  /// Replaces the weights of the first `weights.count` rows of `column`. Weights of rows
  /// further down are kept, for when those rows fill again.
  public mutating func setRowWeights(_ weights: [Double], inColumn column: Int) {
    while rowWeights.count <= column { rowWeights.append([]) }
    var stored = rowWeights[column]
    for (row, weight) in weights.enumerated() {
      if row < stored.count {
        stored[row] = Self.sanitize(weight)
      } else {
        stored.append(Self.sanitize(weight))
      }
    }
    rowWeights[column] = stored
  }

  /// The weights of the first `count` rows of `column`, with 1 for rows that have none.
  public func rowWeights(inColumn column: Int, count: Int) -> [Double] {
    let stored = column < rowWeights.count ? rowWeights[column] : []
    return (0..<count).map { row in row < stored.count ? stored[row] : 1 }
  }

  private static func clamp(_ ratio: Double) -> Double {
    // Rounded to three places so repeated +0.05 / -0.05 steps don't accumulate float noise.
    let rounded = (ratio * 1000).rounded() / 1000
    return rounded.clamped(to: ratioRange)
  }

  /// A weight that can't share out space (zero, negative, infinite, NaN) counts as 1.
  private static func sanitize(_ weight: Double) -> Double {
    weight.isFinite && weight > 0 ? weight : 1
  }
}

/// Turns a window count and an area into one frame per window, in list order. Adding a layout
/// means one new conforming type and one new `LayoutKind` case; the compiler then asks for the
/// case's `implementation` and `symbol`.
public protocol Layout: Sendable {
  func frames(count: Int, in area: CGRect, parameters: LayoutParameters) -> [CGRect]

  /// The parameters that put the edges of window `index` where the user dragged them (`frame`),
  /// or `nil` if the layout doesn't follow that change: no edge it can move was moved. The
  /// other edges are left to snap back. Layouts that don't follow the mouse use the default,
  /// which always returns `nil`.
  func parameters(
    afterResizing index: Int,
    to frame: CGRect,
    count: Int,
    in area: CGRect,
    parameters: LayoutParameters
  ) -> LayoutParameters?
}

extension Layout {
  public func parameters(
    afterResizing index: Int,
    to frame: CGRect,
    count: Int,
    in area: CGRect,
    parameters: LayoutParameters
  ) -> LayoutParameters? {
    nil
  }
}

/// The layouts a workspace can use. `next` cycles through them in declaration order.
public enum LayoutKind: String, Codable, CaseIterable, Sendable {
  case tall
  case full

  public var next: LayoutKind {
    let all = Self.allCases
    guard let index = all.firstIndex(of: self) else { return self }
    return all[(index + 1) % all.count]
  }

  /// The type that works out this layout's frames.
  public var implementation: any Layout {
    switch self {
    case .tall: TallLayout()
    case .full: FullLayout()
    }
  }

  /// How the menu bar item shows this layout.
  public var symbol: String {
    switch self {
    case .tall: "▥"
    case .full: "▢"
    }
  }
}

/// An integer rectangle. Layouts work in whole points so neighbouring windows meet exactly,
/// with no 1pt gaps or overlaps from rounding.
struct IntegerBox: Equatable {
  var minX: Int
  var minY: Int
  var width: Int
  var height: Int

  init(minX: Int, minY: Int, width: Int, height: Int) {
    self.minX = minX
    self.minY = minY
    self.width = max(0, width)
    self.height = max(0, height)
  }

  /// `area` rounded to whole points and shrunk by `inset` on every side.
  init(_ area: CGRect, inset: CGFloat) {
    let gap = Int(inset.rounded())
    self.init(
      minX: Int(area.minX.rounded()) + gap,
      minY: Int(area.minY.rounded()) + gap,
      width: Int(area.width.rounded()) - 2 * gap,
      height: Int(area.height.rounded()) - 2 * gap
    )
  }

  var rect: CGRect {
    CGRect(x: minX, y: minY, width: width, height: height)
  }

  /// Splits a length into one part per weight, in proportion to the weights, separated by
  /// `gap`. The parts add up exactly to `length - gap * (weights.count - 1)`. Each part gets the
  /// whole points of its share, and the points left over go to the parts with the largest
  /// fractions, earliest first on a tie, so equal weights put the remainder in the earliest
  /// parts, and of two parts the first is rounded to the nearest point, halves up.
  static func split(
    origin: Int,
    length: Int,
    weights: [Double],
    gap: Int
  ) -> [(origin: Int, length: Int)] {
    guard !weights.isEmpty else { return [] }
    let available = max(0, length - gap * (weights.count - 1))
    let total = weights.reduce(0, +)
    let shares = weights.map { weight in
      total > 0 ? Double(available) * weight / total : Double(available) / Double(weights.count)
    }
    var sizes = shares.map { Int($0.rounded(.down)) }
    let leftover = available - sizes.reduce(0, +)
    let byFraction = sizes.indices.sorted { first, second in
      let firstFraction = shares[first] - Double(sizes[first])
      let secondFraction = shares[second] - Double(sizes[second])
      // Shares that should tie (1745 × 0.7 and 1745 × 0.3 both end in .5) differ in the last
      // bits, so fractions this close count as equal.
      guard abs(firstFraction - secondFraction) < 1e-9 else {
        return firstFraction > secondFraction
      }
      return first < second
    }
    for index in byFraction.prefix(leftover) {
      sizes[index] += 1
    }
    var parts: [(origin: Int, length: Int)] = []
    var cursor = origin
    for size in sizes {
      parts.append((cursor, size))
      cursor += size + gap
    }
    return parts
  }
}
