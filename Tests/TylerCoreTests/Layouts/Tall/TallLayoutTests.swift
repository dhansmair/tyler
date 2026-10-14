import CoreGraphics
import Testing

@testable import TylerCore

@Suite("TallLayout")
struct TallLayoutTests {
  private let area = CGRect(x: 55, y: 38, width: 1745, height: 1131)
  private let layout = TallLayout()

  private func frames(
    _ count: Int,
    in area: CGRect? = nil,
    state: TallLayoutState = TallLayoutState(),
    gaps: LayoutGaps = LayoutGaps()
  ) -> [CGRect] {
    layout.frames(count: count, in: area ?? self.area, state: state, gaps: gaps)
  }

  @Test func noWindowsGiveNoFrames() {
    #expect(frames(0).isEmpty)
  }

  @Test func oneWindowFillsTheArea() {
    #expect(frames(1) == [CGRect(x: 55, y: 38, width: 1745, height: 1131)])
  }

  @Test func twoWindowsSitSideBySide() throws {
    let result = frames(2, in: CGRect(x: 0, y: 0, width: 1000, height: 600))
    #expect(
      result == [
        CGRect(x: 0, y: 0, width: 500, height: 600),
        CGRect(x: 500, y: 0, width: 500, height: 600),
      ])
  }

  @Test func threeWindowsGiveOneLeftAndTwoStackedRight() {
    let result = frames(3, in: CGRect(x: 0, y: 0, width: 1000, height: 600))
    #expect(
      result == [
        CGRect(x: 0, y: 0, width: 500, height: 600),
        CGRect(x: 500, y: 0, width: 500, height: 300),
        CGRect(x: 500, y: 300, width: 500, height: 300),
      ])
  }

  @Test func theMainRatioMovesTheDivider() {
    let result = frames(
      2, in: CGRect(x: 0, y: 0, width: 1000, height: 600),
      state: TallLayoutState(mainRatio: 0.7))
    #expect(result[0].width == 700)
    #expect(result[1].minX == 700)
    #expect(result[1].width == 300)
  }

  @Test(arguments: 1...9)
  func framesCoverTheAreaExactlyWithoutOverlap(count: Int) {
    // An odd size, so rounding has something to get wrong.
    let odd = CGRect(x: 55, y: 38, width: 1745, height: 1131)
    let result = frames(count, in: odd)
    #expect(result.count == count)
    let covered = result.reduce(0) { $0 + $1.width * $1.height }
    #expect(covered == odd.width * odd.height)
    for (index, first) in result.enumerated() {
      #expect(odd.contains(first))
      for second in result[(index + 1)...] {
        #expect(!first.intersects(second), "\(first) overlaps \(second)")
      }
    }
  }

  @Test func remainderPixelsGoToTheEarliestStackedWindows() {
    // Right column of 3 windows over 100pt: 34, 33, 33.
    let result = frames(4, in: CGRect(x: 0, y: 0, width: 200, height: 100))
    #expect(result.dropFirst().map(\.height) == [34, 33, 33])
  }

  @Test func framesAreWholePoints() {
    for rect in frames(5, in: CGRect(x: 0.4, y: 0.6, width: 1000.3, height: 700.7)) {
      #expect(rect.minX == rect.minX.rounded())
      #expect(rect.minY == rect.minY.rounded())
      #expect(rect.width == rect.width.rounded())
      #expect(rect.height == rect.height.rounded())
    }
  }

  @Test func outerGapInsetsEveryWindowFromTheEdges() {
    let result = frames(
      2, in: CGRect(x: 0, y: 0, width: 1000, height: 600),
      gaps: LayoutGaps(outer: 10))
    #expect(result.map(\.minX).min() == 10)
    #expect(result.map(\.maxX).max() == 990)
    #expect(result.map(\.minY).min() == 10)
    #expect(result.map(\.maxY).max() == 590)
  }

  @Test func innerGapSeparatesNeighbours() {
    let result = frames(
      3, in: CGRect(x: 0, y: 0, width: 1000, height: 600),
      gaps: LayoutGaps(inner: 10))
    // Master and stack are 10pt apart, and so are the two stacked windows.
    #expect(result[1].minX - result[0].maxX == 10)
    #expect(result[2].minY - result[1].maxY == 10)
    // The outer edges still reach the area's edges.
    #expect(result[0].minX == 0)
    #expect(result[1].maxX == 1000)
    #expect(result[2].maxY == 600)
  }

  @Test func gapsNeverOverlapEvenWhenLarge() {
    let result = frames(
      4, in: CGRect(x: 0, y: 0, width: 300, height: 200),
      gaps: LayoutGaps(inner: 40, outer: 40))
    for (index, first) in result.enumerated() {
      for second in result[(index + 1)...] {
        #expect(!first.intersects(second))
      }
    }
  }

  @Test func rowWeightsSetTheStackHeights() {
    let result = frames(
      3, in: CGRect(x: 0, y: 0, width: 1000, height: 600),
      state: TallLayoutState(rowWeights: [[], [2, 1]]))
    #expect(result[0] == CGRect(x: 0, y: 0, width: 500, height: 600), "the master is unchanged")
    #expect(result[1] == CGRect(x: 500, y: 0, width: 500, height: 400))
    #expect(result[2] == CGRect(x: 500, y: 400, width: 500, height: 200))
  }

  @Test func rowsWithoutAWeightWeighOne() {
    // Weights for two rows, three stacked windows: the third weighs 1.
    let result = frames(
      4, in: CGRect(x: 0, y: 0, width: 1000, height: 400),
      state: TallLayoutState(rowWeights: [[], [2, 1]]))
    #expect(result.dropFirst().map(\.height) == [200, 100, 100])
  }

  @Test func extraRowWeightsAreIgnoredButKept() {
    let state = TallLayoutState(rowWeights: [[], [3, 1, 4]])
    let result = frames(3, in: CGRect(x: 0, y: 0, width: 1000, height: 400), state: state)
    #expect(result.dropFirst().map(\.height) == [300, 100])
    #expect(state.rowWeights == [[], [3, 1, 4]], "for when the window comes back")
  }

  @Test func rowWeightsKeepTheInnerGap() {
    let result = frames(
      3, in: CGRect(x: 0, y: 0, width: 1000, height: 610),
      state: TallLayoutState(rowWeights: [[], [1, 2]]),
      gaps: LayoutGaps(inner: 10))
    #expect(result[1].height == 200)
    #expect(result[2].minY - result[1].maxY == 10)
    #expect(result[2].height == 400)
  }

  @Test(arguments: [[3.0, 1, 1], [1, 7, 2.5], [0.1, 0.1, 5]])
  func weightedRowsStillCoverTheColumnExactly(weights: [Double]) {
    let odd = CGRect(x: 55, y: 38, width: 1745, height: 1131)
    let result = frames(
      4, in: odd, state: TallLayoutState(rowWeights: [[], weights]))
    #expect(result.dropFirst().map(\.height).reduce(0, +) == odd.height)
    for (upper, lower) in zip(result.dropFirst(), result.dropFirst(2)) {
      #expect(upper.maxY == lower.minY)
    }
  }

  @Test func aTinyAreaDoesNotProduceNegativeSizes() {
    for rect in frames(5, in: CGRect(x: 0, y: 0, width: 10, height: 10)) {
      #expect(rect.width >= 0)
      #expect(rect.height >= 0)
    }
  }
}
