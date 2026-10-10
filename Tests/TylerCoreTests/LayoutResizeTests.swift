import CoreGraphics
import Testing

@testable import TylerCore

/// Tall with three windows in 1000 × 600: the master is (0, 0, 500, 600), the stack is
/// (500, 0, 500, 300) above (500, 300, 500, 300).
@Suite("Resizing tall with the mouse")
struct TallResizeTests {
  private let area = CGRect(x: 0, y: 0, width: 1000, height: 600)
  private let layout = TallLayout()

  private func resized(
    _ index: Int,
    to frame: CGRect,
    count: Int = 3,
    parameters: LayoutParameters = LayoutParameters()
  ) -> LayoutParameters? {
    layout.parameters(
      afterResizing: index, to: frame, count: count, in: area, parameters: parameters)
  }

  @Test func draggingTheFirstColumnsRightEdgeSetsTheRatio() {
    let updated = resized(0, to: CGRect(x: 0, y: 0, width: 600, height: 600))
    #expect(updated?.mainRatio == 0.6)
  }

  @Test func draggingAStackedWindowsLeftEdgeSetsTheRatio() {
    let updated = resized(1, to: CGRect(x: 400, y: 0, width: 600, height: 300))
    #expect(updated?.mainRatio == 0.4)
  }

  @Test func draggingTheDividerBelowAStackedWindowSplitsTheStack() throws {
    let updated = try #require(resized(1, to: CGRect(x: 500, y: 0, width: 500, height: 400)))
    #expect(updated.mainRatio == 0.5)
    let frames = layout.frames(count: 3, in: area, parameters: updated)
    #expect(frames[1] == CGRect(x: 500, y: 0, width: 500, height: 400))
    #expect(frames[2] == CGRect(x: 500, y: 400, width: 500, height: 200))
  }

  @Test func draggingTheDividerAboveAStackedWindowSplitsTheStack() throws {
    let updated = try #require(resized(2, to: CGRect(x: 500, y: 200, width: 500, height: 400)))
    let frames = layout.frames(count: 3, in: area, parameters: updated)
    #expect(frames[1].height == 200)
    #expect(frames[2] == CGRect(x: 500, y: 200, width: 500, height: 400))
  }

  @Test func draggingACornerMovesBothDividers() throws {
    let updated = try #require(resized(2, to: CGRect(x: 450, y: 200, width: 550, height: 400)))
    #expect(updated.mainRatio == 0.45)
    let frames = layout.frames(count: 3, in: area, parameters: updated)
    #expect(frames[2] == CGRect(x: 450, y: 200, width: 550, height: 400))
  }

  @Test func aDividerStopsShortOfSqueezingANeighbourAway() throws {
    let wide = try #require(resized(0, to: CGRect(x: 0, y: 0, width: 995, height: 600)))
    #expect(wide.mainRatio == LayoutParameters.ratioRange.upperBound)
    let tall = try #require(resized(1, to: CGRect(x: 500, y: 0, width: 500, height: 598)))
    let frames = layout.frames(count: 3, in: area, parameters: tall)
    #expect(frames[1].height == 540)
    #expect(frames[2].height == 60, "10% of the two rows")
  }

  @Test(
    arguments: [
      // The master's top, bottom and left edges are the area's edges.
      (0, CGRect(x: 0, y: 50, width: 500, height: 550)),
      (0, CGRect(x: 0, y: 0, width: 500, height: 500)),
      (0, CGRect(x: 20, y: 0, width: 480, height: 600)),
      // The stack's right edge, the top of the first row and the bottom of the last.
      (1, CGRect(x: 500, y: 0, width: 450, height: 300)),
      (1, CGRect(x: 500, y: 30, width: 500, height: 270)),
      (2, CGRect(x: 500, y: 300, width: 500, height: 250)),
      // Moved, not resized: both opposite edges moved.
      (1, CGRect(x: 520, y: 20, width: 500, height: 300)),
      // Unchanged, or within a point.
      (1, CGRect(x: 501, y: 0, width: 499, height: 300)),
    ])
  func edgesThatAreNotDividersAreIgnored(index: Int, frame: CGRect) {
    #expect(resized(index, to: frame) == nil)
  }

  @Test func aSingleWindowHasNoDividers() {
    #expect(resized(0, to: CGRect(x: 0, y: 0, width: 700, height: 600), count: 1) == nil)
  }

  @Test func otherRowsKeepTheirWeights() throws {
    let parameters = LayoutParameters(rowWeights: [[], [1, 1, 2, 5]])
    // Four windows: a stack of three, 150 / 150 / 300 high. Drag the first divider down 50.
    let updated = try #require(
      resized(
        1, to: CGRect(x: 500, y: 0, width: 500, height: 200), count: 4, parameters: parameters))
    let weights = updated.rowWeights[1]
    #expect(weights.count == 4, "the weight of the empty fourth row is kept")
    #expect(weights[2] == 2)
    #expect(weights[3] == 5)
    #expect(abs(weights[0] + weights[1] - 2) < 1e-9, "the pair keeps its total")
    let frames = layout.frames(count: 4, in: area, parameters: updated)
    #expect(frames.dropFirst().map(\.height) == [200, 100, 300])
  }

  @Test(arguments: [3, 77, 123, 260, 341, 420])
  func theLayoutPutsADraggedDividerWhereItWasDragged(offset: Int) throws {
    // With gaps and an odd area, so rounding has something to get wrong.
    let odd = CGRect(x: 55, y: 38, width: 1745, height: 1131)
    let parameters = LayoutParameters(outerGap: 8, innerGap: 12)
    let before = layout.frames(count: 3, in: odd, parameters: parameters)
    var dragged = before[1]
    dragged.size.height += CGFloat(offset)
    let updated = try #require(
      layout.parameters(
        afterResizing: 1, to: dragged, count: 3, in: odd, parameters: parameters))
    let after = layout.frames(count: 3, in: odd, parameters: updated)
    #expect(abs(after[1].maxY - dragged.maxY) <= 1)
    #expect(after[2].minY - after[1].maxY == 12, "the gap stays")
  }
}

@Suite("Resizing other layouts with the mouse")
struct OtherLayoutResizeTests {
  @Test func fullDoesNotFollowTheMouse() {
    let area = CGRect(x: 0, y: 0, width: 1000, height: 600)
    let updated = FullLayout().parameters(
      afterResizing: 0, to: CGRect(x: 0, y: 0, width: 600, height: 600), count: 2, in: area,
      parameters: LayoutParameters())
    #expect(updated == nil)
  }

  @Test func aMiddleColumnMovesTheDividerOnTheSideThatWasDragged() throws {
    let columns = ColumnLayout(rowCounts: [1, 1, 1], columnWeights: [1, 1, 1])
    let area = CGRect(x: 0, y: 0, width: 900, height: 300)
    let left = try #require(
      columns.resize(
        index: 1, to: CGRect(x: 250, y: 0, width: 350, height: 300), in: area,
        parameters: LayoutParameters()))
    #expect(left.columnWidths == [250, 350, 300])
    let right = try #require(
      columns.resize(
        index: 1, to: CGRect(x: 300, y: 0, width: 400, height: 300), in: area,
        parameters: LayoutParameters()))
    #expect(right.columnWidths == [300, 400, 200])
  }
}
