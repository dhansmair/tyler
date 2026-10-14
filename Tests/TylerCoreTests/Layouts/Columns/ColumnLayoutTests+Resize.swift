import CoreGraphics
import Testing

@testable import TylerCore

@Suite("Columns: resizing with the mouse")
struct ColumnLayoutResizeTests {
  @Test func aMiddleColumnMovesTheDividerOnTheSideThatWasDragged() throws {
    let area = CGRect(x: 0, y: 0, width: 900, height: 300)
    let left = try #require(
      Self.columnWidths(
        afterResizing: 1, to: CGRect(x: 250, y: 0, width: 350, height: 300), in: area))
    #expect(left == [250, 350, 300])
    let right = try #require(
      Self.columnWidths(
        afterResizing: 1, to: CGRect(x: 300, y: 0, width: 400, height: 300), in: area))
    #expect(right == [300, 400, 200])
  }

  /// The widths three equal columns of one window each get after window `index` is resized to
  /// `frame`, or `nil` if no divider moved.
  private static func columnWidths(
    afterResizing index: Int, to frame: CGRect, in area: CGRect
  ) -> [Int]? {
    let columns = ColumnLayout(rowCounts: [1, 1, 1], columnWeights: [1, 1, 1])
    guard let weights = columns.resize(index: index, to: frame, in: area, gaps: LayoutGaps())
    else { return nil }
    let resized = ColumnLayout(rowCounts: [1, 1, 1], weights: weights)
    return resized.frames(in: area, gaps: LayoutGaps())
      .map { Int($0.width) }
  }
}
