import CoreGraphics
import Testing

@testable import TylerCore

private let half = WindowSize.half
private let full = WindowSize.full
private let quarter = WindowSize.quarter

@Suite("Strip layout: frames")
struct StripLayoutTests {
  private let area = CGRect(x: 0, y: 0, width: 1000, height: 600)

  private func frames(
    _ sizes: [WindowSize], firstVisible: Int = 0, in area: CGRect? = nil,
    gaps: LayoutGaps = LayoutGaps()
  ) -> [CGRect] {
    StripLayout().frames(
      of: windowIDs(count: sizes.count),
      state: StripLayoutState(
        sizes: Dictionary(uniqueKeysWithValues: zip(windowIDs(count: sizes.count), sizes))),
      startingAt: firstVisible, in: area ?? self.area, gaps: gaps)
  }

  @Test func noWindowsGiveNoFrames() {
    #expect(frames([]).isEmpty)
  }

  @Test func twoHalvesLookLikeTall() {
    // With gaps and an odd area, so the rounding has to agree too.
    let odd = CGRect(x: 55, y: 38, width: 1745, height: 1131)
    let gaps = LayoutGaps(inner: 8, outer: 12)
    #expect(
      frames([half, half], in: odd, gaps: gaps)
        == TallLayout().frames(count: 2, in: odd, gaps: gaps))
  }

  @Test func aFullWindowLooksLikeFull() {
    let gaps = LayoutGaps(inner: 8, outer: 12)
    #expect(frames([full], gaps: gaps) == FullLayout().frames(count: 1, in: area, gaps: gaps))
  }

  @Test func twoQuartersShareAColumn() {
    #expect(
      frames([quarter, quarter, half]) == [
        CGRect(x: 0, y: 0, width: 500, height: 300),
        CGRect(x: 0, y: 300, width: 500, height: 300),
        CGRect(x: 500, y: 0, width: 500, height: 600),
      ])
  }

  @Test func aQuarterOnItsOwnFillsItsColumn() {
    #expect(frames([quarter])[0] == CGRect(x: 0, y: 0, width: 500, height: 600))
  }

  @Test func columnsLeftOfTheViewLieOffItsLeftEdge() {
    let result = frames([half, half, half, half], firstVisible: 2)
    #expect(result.map(\.minX) == [-1000, -500, 0, 500])
  }

  @Test func columnsFollowEachOtherWithoutAGap() {
    let result = frames([half, full, half])
    #expect(result.map(\.minX) == [0, 500, 1500])
    #expect(result.map(\.width) == [500, 1000, 500])
  }

  @Test func columnsOutOfViewLieWhollyOffTheAreaWithAWiderOuterGap() {
    let gaps = LayoutGaps(inner: 4, outer: 20)
    #expect(frames([half, half, half], gaps: gaps)[2].minX == area.maxX)
    #expect(frames([half, half, half], firstVisible: 1, gaps: gaps)[0].maxX == area.minX)
  }

  @Test func pagesIncludeTheInnerGap() {
    let result = frames(
      [half, half, half, half], in: CGRect(x: 0, y: 0, width: 1010, height: 600),
      gaps: LayoutGaps(inner: 10))
    #expect(result.map(\.minX) == [0, 510, 1020, 1530])
    #expect(result.map(\.width) == [500, 500, 500, 500])
  }

  @Test func anyWindowOfAColumnPicksIt() {
    #expect(frames([half, quarter, quarter, half], firstVisible: 2)[1].minX == 0)
  }

  @Test func missingSizesCountAsHalf() {
    let state = StripLayoutState(sizes: [WindowID(1): full])
    #expect(windowIDs(count: 3).map(state.size(of:)) == [full, half, half])
  }

  @Test func sizesCycle() {
    #expect(WindowSize.allCases.map(\.next) == [full, quarter, half])
  }
}
