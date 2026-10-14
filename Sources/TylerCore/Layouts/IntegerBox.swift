import CoreGraphics

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
