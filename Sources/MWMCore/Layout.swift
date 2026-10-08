import CoreGraphics

/// Tunable inputs to every layout. Gaps are in points; the master ratio is clamped to
/// `ratioRange` so neither column of a tall layout can vanish.
public struct LayoutParameters: Equatable, Sendable {
  public static let ratioRange: ClosedRange<Double> = 0.1...0.9

  public private(set) var mainRatio: Double
  /// Space between the layout area's edge and the windows.
  public let outerGap: CGFloat
  /// Space between neighbouring windows.
  public let innerGap: CGFloat

  public init(mainRatio: Double = 0.5, outerGap: CGFloat = 0, innerGap: CGFloat = 0) {
    self.mainRatio = Self.clamp(mainRatio)
    self.outerGap = max(0, outerGap)
    self.innerGap = max(0, innerGap)
  }

  /// Moves the ratio by `delta`, staying inside `ratioRange`. Returns whether it changed.
  @discardableResult
  public mutating func adjustRatio(by delta: Double) -> Bool {
    let updated = Self.clamp(mainRatio + delta)
    guard updated != mainRatio else { return false }
    mainRatio = updated
    return true
  }

  private static func clamp(_ ratio: Double) -> Double {
    // Rounded to three places so repeated +0.05 / -0.05 steps don't accumulate float noise.
    let rounded = (ratio * 1000).rounded() / 1000
    return min(max(rounded, ratioRange.lowerBound), ratioRange.upperBound)
  }
}

/// Turns a window count and an area into one frame per window, in list order. Adding a layout
/// means one new conforming type and one new `LayoutKind` case.
public protocol Layout: Sendable {
  func frames(count: Int, in area: CGRect, parameters: LayoutParameters) -> [CGRect]
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

  public var layout: any Layout {
    switch self {
    case .tall: TallLayout()
    case .full: FullLayout()
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

  /// Splits a length into `count` parts separated by `gap`. The parts add up exactly to
  /// `length - gap * (count - 1)`, with any remainder going to the earliest parts.
  static func split(
    origin: Int,
    length: Int,
    count: Int,
    gap: Int
  ) -> [(origin: Int, length: Int)] {
    guard count > 0 else { return [] }
    let available = max(0, length - gap * (count - 1))
    let base = available / count
    let extra = available % count
    var parts: [(origin: Int, length: Int)] = []
    var cursor = origin
    for index in 0..<count {
      let size = base + (index < extra ? 1 : 0)
      parts.append((cursor, size))
      cursor += size + gap
    }
    return parts
  }
}
