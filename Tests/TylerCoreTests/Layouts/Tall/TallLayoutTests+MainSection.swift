import CoreGraphics
import Testing

@testable import TylerCore

@Suite("Tall with several masters")
struct TallLayoutMainSectionTests {
  private let area = CGRect(x: 0, y: 0, width: 1000, height: 600)
  private let layout = TallLayout()

  @Test func twoMainsAreStackedInTheLeftColumn() {
    let frames = layout.frames(count: 3, in: area, state: TallLayoutState(mainCount: 2))
    #expect(
      frames == [
        CGRect(x: 0, y: 0, width: 500, height: 300),
        CGRect(x: 0, y: 300, width: 500, height: 300),
        CGRect(x: 500, y: 0, width: 500, height: 600),
      ])
  }

  @Test(arguments: [2, 3, 5])
  func everyWindowAMainGivesOneColumn(mainCount: Int) {
    let frames = layout.frames(count: 2, in: area, state: TallLayoutState(mainCount: mainCount))
    #expect(
      frames == [
        CGRect(x: 0, y: 0, width: 1000, height: 300),
        CGRect(x: 0, y: 300, width: 1000, height: 300),
      ])
  }

  @Test(arguments: [0, -1])
  func theMainSectionHoldsAtLeastOneWindow(mainCount: Int) {
    #expect(TallLayoutState(mainCount: mainCount).mainCount(for: 3) == 1)
  }

  @Test func draggingTheDividerBetweenTwoMainsSplitsTheLeftColumn() throws {
    let state = TallLayoutState(mainCount: 2)
    let updated = try #require(
      layout.state(
        afterResizing: 0, to: CGRect(x: 0, y: 0, width: 500, height: 400), count: 3, in: area,
        state: state))
    #expect(updated.mainRatio == 0.5)
    let frames = layout.frames(count: 3, in: area, state: updated)
    #expect(frames[0] == CGRect(x: 0, y: 0, width: 500, height: 400))
    #expect(frames[1] == CGRect(x: 0, y: 400, width: 500, height: 200))
  }

  @Test func inOneColumnAWidthDragChangesNothing() {
    let updated = layout.state(
      afterResizing: 0, to: CGRect(x: 0, y: 0, width: 700, height: 300), count: 2, in: area,
      state: TallLayoutState(mainCount: 2))
    #expect(updated == nil)
  }
}
