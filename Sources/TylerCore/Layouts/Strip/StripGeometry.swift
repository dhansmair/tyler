import CoreGraphics

/// Turns positions in halves of the view into points. A page (two halves) is the area's width
/// minus the outer gaps, plus an inner gap, so a view of two half columns or one full column
/// fills the area exactly as `tall` with two windows and `full` do.
struct StripGeometry {
  private let box: IntegerBox
  private let page: Int
  private let firstHalf: (origin: Int, length: Int)
  private let secondHalf: (origin: Int, length: Int)
  private let areaMinX: Int
  private let areaMaxX: Int
  let fullRow: (origin: Int, length: Int)
  let halfRows: [(origin: Int, length: Int)]

  init(area: CGRect, gaps: LayoutGaps) {
    box = IntegerBox(area, inset: gaps.outer)
    areaMinX = Int(area.minX.rounded(.down))
    areaMaxX = Int(area.maxX.rounded(.up))
    let gap = Int(gaps.inner.rounded())
    page = box.width + gap
    let halves = IntegerBox.split(origin: box.minX, length: box.width, weights: [1, 1], gap: gap)
    firstHalf = halves[0]
    secondHalf = halves[1]
    fullRow = (box.minY, box.height)
    halfRows = IntegerBox.split(origin: box.minY, length: box.height, weights: [1, 1], gap: gap)
  }

  /// The left edge of a column that starts `position` halves from the view's left edge.
  func left(at position: Int) -> Int {
    let (pages, isSecondHalf) = Self.split(position)
    return pages * page + (isSecondHalf ? secondHalf.origin : firstHalf.origin)
  }

  /// Like `left(at:)`, but a column wholly out of view is moved clear of the area: with an outer
  /// gap wider than the inner one, it would otherwise reach into the outer gap and count as
  /// partly in view.
  func left(ofColumnAt position: Int, halves: Int) -> Int {
    let left = left(at: position)
    if position >= StripColumns.viewWidth { return max(left, areaMaxX) }
    if position + halves <= 0 { return min(left, areaMinX - width(of: halves, at: position)) }
    return left
  }

  /// The width of a column `halves` wide that starts at `position`.
  func width(of halves: Int, at position: Int) -> Int {
    guard halves == 1 else { return box.width }
    return Self.split(position).isSecondHalf ? secondHalf.length : firstHalf.length
  }

  /// Whole pages to the left of `position` (rounded down, also left of the view), and whether
  /// it is the second half of its page.
  private static func split(_ position: Int) -> (pages: Int, isSecondHalf: Bool) {
    let pages = position >= 0 ? position / 2 : (position - 1) / 2
    return (pages, position - pages * 2 == 1)
  }
}
