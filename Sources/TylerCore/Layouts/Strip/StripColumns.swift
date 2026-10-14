import CoreGraphics

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
