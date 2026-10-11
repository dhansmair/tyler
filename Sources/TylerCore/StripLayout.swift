import CoreGraphics

/// How much of the display a window takes in the strip layout.
public enum WindowSize: String, Codable, CaseIterable, Sendable {
  /// Half the width and the full height. New windows start like this, so two windows side by
  /// side look like `tall`.
  case half
  /// The full width and height.
  case full
  /// Half the width and half the height. Two in a row share a column, one above the other; one
  /// on its own fills its column like `half`.
  case quarter

  /// The size after this one, in declaration order, wrapping around.
  public var next: WindowSize {
    let all = Self.allCases
    guard let index = all.firstIndex(of: self) else { return self }
    return all[(index + 1) % all.count]
  }
}

/// niri's scrolling layout: the windows form one long row of columns, left to right in list
/// order, and the display shows a view of it. Each window's size says how wide its column is.
/// Columns out of view get frames off the area, to the left or right; the workspace parks them.
public struct StripLayout: Layout {
  public init() {}

  public func frames(for input: LayoutInput, in area: CGRect, gaps: LayoutGaps) -> [CGRect] {
    let columns = StripColumns(sizes: input.windowSizes)
    guard let start = columns.column(of: input.firstVisible) ?? columns.columns.indices.first
    else { return [] }
    let visible = columns.visible(from: start)
    let geometry = StripGeometry(area: area, gaps: gaps)
    var frames = Array(repeating: CGRect.zero, count: input.count)
    for (column, members) in columns.columns.enumerated() {
      // Columns after the view start on the next page, so none of them shows at its edge.
      let position =
        column < visible.upperBound
        ? columns.offset(of: column) - columns.offset(of: start)
        : StripColumns.viewWidth + columns.offset(of: column)
          - columns.offset(of: visible.upperBound)
      let left = geometry.left(at: position)
      let width = geometry.width(of: columns.widths[column], at: position)
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

/// The strip's windows grouped into columns. Widths and positions are in halves of the view,
/// which is two halves wide.
struct StripColumns: Equatable {
  static let viewWidth = 2

  /// Window indices per column, left to right.
  let columns: [[Int]]
  /// Each column's width: 1 (half) or 2 (full).
  let widths: [Int]

  /// `full` and `half` windows each make a column; two `quarter`s in a row share one.
  init(sizes: [WindowSize]) {
    var columns: [[Int]] = []
    var widths: [Int] = []
    var index = 0
    while index < sizes.count {
      let pairs =
        sizes[index] == .quarter && index + 1 < sizes.count && sizes[index + 1] == .quarter
      columns.append(pairs ? [index, index + 1] : [index])
      widths.append(sizes[index] == .full ? 2 : 1)
      index += pairs ? 2 : 1
    }
    self.columns = columns
    self.widths = widths
  }

  /// The column that window `index` is in.
  func column(of index: Int) -> Int? {
    columns.firstIndex { $0.contains(index) }
  }

  /// Where `column` starts, counted from the strip's left end.
  func offset(of column: Int) -> Int {
    widths[..<column].reduce(0, +)
  }

  /// The columns in view when `start` is the leftmost one: as many whole columns as fit, and at
  /// least that one.
  func visible(from start: Int) -> Range<Int> {
    var end = start
    var used = 0
    while end < widths.count, end == start || used + widths[end] <= Self.viewWidth {
      used += widths[end]
      end += 1
    }
    return start..<end
  }

  /// The leftmost column after a change, starting from `previous`: scrolled just far enough to
  /// show the `focused` column whole, and never showing empty space past the strip's end.
  func fittedStart(previous: Int, focused: Int?) -> Int {
    guard !widths.isEmpty else { return 0 }
    var start = min(max(previous, 0), widths.count - 1)
    if let focused {
      if focused < start {
        start = focused
      } else if focused >= visible(from: start).upperBound {
        start = focused
        while start > 0, widths[(start - 1)...focused].reduce(0, +) <= Self.viewWidth {
          start -= 1
        }
      }
    }
    return clampedToEnd(start)
  }

  /// `start` moved left while the view reaches the last column and a column more on the left
  /// still fits, so the view never shows empty space after the strip's end.
  func clampedToEnd(_ start: Int) -> Int {
    var start = start
    while hasRoomOnTheLeft(start) { start -= 1 }
    return start
  }

  /// Whether the view starting at `start` reaches the last column with room for the column on
  /// its left too.
  private func hasRoomOnTheLeft(_ start: Int) -> Bool {
    start > 0 && visible(from: start).upperBound == widths.count
      && widths[(start - 1)...].reduce(0, +) <= Self.viewWidth
  }

  /// The columns the view can start at, left to right: where a swipe can settle.
  var starts: [Int] {
    widths.indices.filter { clampedToEnd($0) == $0 }
  }
}

/// Turns positions in halves of the view into points. A page (two halves) is the area's width
/// minus the outer gaps, plus an inner gap, so a view of two half columns or one full column
/// fills the area exactly as `tall` with two windows and `full` do.
struct StripGeometry {
  private let box: IntegerBox
  private let page: Int
  private let firstHalf: (origin: Int, length: Int)
  private let secondHalf: (origin: Int, length: Int)
  let fullRow: (origin: Int, length: Int)
  let halfRows: [(origin: Int, length: Int)]

  init(area: CGRect, gaps: LayoutGaps) {
    box = IntegerBox(area, inset: gaps.outer)
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
