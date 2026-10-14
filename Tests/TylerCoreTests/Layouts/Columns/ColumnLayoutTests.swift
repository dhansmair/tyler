import CoreGraphics
import Testing

@testable import TylerCore

@Suite("ColumnLayout")
struct ColumnLayoutTests {
  @Test func columnsFillLeftToRightAndRowsTopToBottom() {
    let layout = ColumnLayout(rowCounts: [2, 3], columnWeights: [1, 1])
    let result = layout.frames(
      in: CGRect(x: 0, y: 0, width: 1000, height: 600), gaps: LayoutGaps())
    #expect(
      result == [
        CGRect(x: 0, y: 0, width: 500, height: 300),
        CGRect(x: 0, y: 300, width: 500, height: 300),
        CGRect(x: 500, y: 0, width: 500, height: 200),
        CGRect(x: 500, y: 200, width: 500, height: 200),
        CGRect(x: 500, y: 400, width: 500, height: 200),
      ])
  }

  @Test func moreThanTwoColumnsShareTheWidthByWeight() {
    let layout = ColumnLayout(rowCounts: [1, 1, 1], columnWeights: [1, 2, 1])
    let result = layout.frames(
      in: CGRect(x: 0, y: 0, width: 400, height: 100), gaps: LayoutGaps())
    #expect(result.map(\.minX) == [0, 100, 300])
    #expect(result.map(\.width) == [100, 200, 100])
  }

  @Test func eachColumnHasItsOwnRowWeights() {
    let layout = ColumnLayout(
      rowCounts: [2, 2], columnWeights: [1, 1], rowWeights: [[1, 3], [1, 1]])
    let result = layout.frames(in: CGRect(x: 0, y: 0, width: 200, height: 400), gaps: LayoutGaps())
    #expect(result.map(\.height) == [100, 300, 200, 200])
  }

  @Test func noWindowsGiveNoFrames() {
    let layout = ColumnLayout(rowCounts: [0], columnWeights: [1])
    #expect(
      layout.frames(
        in: CGRect(x: 0, y: 0, width: 10, height: 10), gaps: LayoutGaps()
      )
      .isEmpty)
  }
}
