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
    parameters: LayoutParameters = LayoutParameters()
  ) -> [CGRect] {
    layout.frames(count: count, in: area ?? self.area, parameters: parameters)
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
      parameters: LayoutParameters(mainRatio: 0.7))
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
      parameters: LayoutParameters(outerGap: 10))
    #expect(result.map(\.minX).min() == 10)
    #expect(result.map(\.maxX).max() == 990)
    #expect(result.map(\.minY).min() == 10)
    #expect(result.map(\.maxY).max() == 590)
  }

  @Test func innerGapSeparatesNeighbours() {
    let result = frames(
      3, in: CGRect(x: 0, y: 0, width: 1000, height: 600),
      parameters: LayoutParameters(innerGap: 10))
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
      parameters: LayoutParameters(outerGap: 40, innerGap: 40))
    for (index, first) in result.enumerated() {
      for second in result[(index + 1)...] {
        #expect(!first.intersects(second))
      }
    }
  }

  @Test func rowWeightsSetTheStackHeights() {
    let result = frames(
      3, in: CGRect(x: 0, y: 0, width: 1000, height: 600),
      parameters: LayoutParameters(rowWeights: [[], [2, 1]]))
    #expect(result[0] == CGRect(x: 0, y: 0, width: 500, height: 600), "the master is unchanged")
    #expect(result[1] == CGRect(x: 500, y: 0, width: 500, height: 400))
    #expect(result[2] == CGRect(x: 500, y: 400, width: 500, height: 200))
  }

  @Test func rowsWithoutAWeightWeighOne() {
    // Weights for two rows, three stacked windows: the third weighs 1.
    let result = frames(
      4, in: CGRect(x: 0, y: 0, width: 1000, height: 400),
      parameters: LayoutParameters(rowWeights: [[], [2, 1]]))
    #expect(result.dropFirst().map(\.height) == [200, 100, 100])
  }

  @Test func extraRowWeightsAreIgnoredButKept() {
    let parameters = LayoutParameters(rowWeights: [[], [3, 1, 4]])
    let result = frames(3, in: CGRect(x: 0, y: 0, width: 1000, height: 400), parameters: parameters)
    #expect(result.dropFirst().map(\.height) == [300, 100])
    #expect(parameters.rowWeights == [[], [3, 1, 4]], "for when the window comes back")
  }

  @Test func rowWeightsKeepTheInnerGap() {
    let result = frames(
      3, in: CGRect(x: 0, y: 0, width: 1000, height: 610),
      parameters: LayoutParameters(rowWeights: [[], [1, 2]], innerGap: 10))
    #expect(result[1].height == 200)
    #expect(result[2].minY - result[1].maxY == 10)
    #expect(result[2].height == 400)
  }

  @Test(arguments: [[3.0, 1, 1], [1, 7, 2.5], [0.1, 0.1, 5]])
  func weightedRowsStillCoverTheColumnExactly(weights: [Double]) {
    let odd = CGRect(x: 55, y: 38, width: 1745, height: 1131)
    let result = frames(4, in: odd, parameters: LayoutParameters(rowWeights: [[], weights]))
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

@Suite("ColumnLayout")
struct ColumnLayoutTests {
  @Test func columnsFillLeftToRightAndRowsTopToBottom() {
    let layout = ColumnLayout(rowCounts: [2, 3], columnWeights: [1, 1])
    let result = layout.frames(
      in: CGRect(x: 0, y: 0, width: 1000, height: 600), parameters: LayoutParameters())
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
      in: CGRect(x: 0, y: 0, width: 400, height: 100), parameters: LayoutParameters())
    #expect(result.map(\.minX) == [0, 100, 300])
    #expect(result.map(\.width) == [100, 200, 100])
  }

  @Test func eachColumnHasItsOwnRowWeights() {
    let layout = ColumnLayout(rowCounts: [2, 2], columnWeights: [1, 1])
    let result = layout.frames(
      in: CGRect(x: 0, y: 0, width: 200, height: 400),
      parameters: LayoutParameters(rowWeights: [[1, 3], [1, 1]]))
    #expect(result.map(\.height) == [100, 300, 200, 200])
  }

  @Test func noWindowsGiveNoFrames() {
    let layout = ColumnLayout(rowCounts: [0], columnWeights: [1])
    #expect(
      layout.frames(in: CGRect(x: 0, y: 0, width: 10, height: 10), parameters: LayoutParameters())
        .isEmpty)
  }
}

@Suite("IntegerBox.split")
struct IntegerBoxSplitTests {
  @Test func equalWeightsGiveTheRemainderToTheEarliestParts() {
    let parts = IntegerBox.split(origin: 0, length: 100, weights: [1, 1, 1], gap: 0)
    #expect(parts.map(\.length) == [34, 33, 33])
  }

  @Test(arguments: [(0.5, 873), (0.7, 1222), (0.3, 524), (0.123, 215), (0.877, 1530)])
  func twoPartsRoundTheFirstToTheNearestPointHalvesUp(ratio: Double, expected: Int) {
    // 1745 points: 872.5, 1221.5 and 523.5 are halves; 214.6 and 1530.4 are not.
    let parts = IntegerBox.split(origin: 0, length: 1745, weights: [ratio, 1 - ratio], gap: 0)
    #expect(parts[0].length == expected)
    #expect(parts[1].length == 1745 - expected)
  }

  @Test func zeroTotalWeightSplitsEvenly() {
    let parts = IntegerBox.split(origin: 10, length: 90, weights: [0, 0, 0], gap: 0)
    #expect(parts.map(\.length) == [30, 30, 30])
    #expect(parts.map(\.origin) == [10, 40, 70])
  }

  @Test func noWeightsGiveNoParts() {
    #expect(IntegerBox.split(origin: 0, length: 100, weights: [], gap: 5).isEmpty)
  }
}

@Suite("FullLayout")
struct FullLayoutTests {
  private let area = CGRect(x: 55, y: 38, width: 1745, height: 1131)

  @Test func everyWindowGetsTheWholeArea() {
    let result = FullLayout().frames(count: 3, in: area, parameters: LayoutParameters())
    #expect(result == Array(repeating: area, count: 3))
  }

  @Test func noWindowsGiveNoFrames() {
    #expect(FullLayout().frames(count: 0, in: area, parameters: LayoutParameters()).isEmpty)
  }

  @Test func outerGapApplies() {
    let result = FullLayout().frames(
      count: 1, in: CGRect(x: 0, y: 0, width: 100, height: 100),
      parameters: LayoutParameters(outerGap: 5))
    #expect(result == [CGRect(x: 5, y: 5, width: 90, height: 90)])
  }
}

@Suite("LayoutKind and parameters")
struct LayoutKindTests {
  @Test func nextCyclesAndWraps() {
    #expect(LayoutKind.tall.next == .full)
    #expect(LayoutKind.full.next == .tall)
  }

  @Test(arguments: LayoutKind.allCases)
  func everyKindProducesALayout(kind: LayoutKind) {
    let frames = kind.layout.frames(
      count: 2, in: CGRect(x: 0, y: 0, width: 100, height: 100), parameters: LayoutParameters())
    #expect(frames.count == 2)
  }

  @Test func ratioIsClampedOnCreation() {
    #expect(LayoutParameters(mainRatio: 0.0).mainRatio == 0.1)
    #expect(LayoutParameters(mainRatio: 5).mainRatio == 0.9)
  }

  @Test func adjustingTheRatioStaysInRangeAndReportsChange() {
    var parameters = LayoutParameters(mainRatio: 0.85)
    let didChange = parameters.adjustRatio(by: 0.05)
    #expect(didChange)
    #expect(parameters.mainRatio == 0.9)
    let didChange2 = parameters.adjustRatio(by: 0.05)
    #expect(!didChange2, "already at the limit")
    #expect(parameters.mainRatio == 0.9)
  }

  @Test func repeatedStepsDoNotAccumulateFloatingPointNoise() {
    var parameters = LayoutParameters(mainRatio: 0.5)
    for _ in 0..<7 { parameters.adjustRatio(by: 0.05) }
    for _ in 0..<7 { parameters.adjustRatio(by: -0.05) }
    #expect(parameters.mainRatio == 0.5)
  }

  @Test func changingTheGapsKeepsTheRatio() {
    let parameters = LayoutParameters(mainRatio: 0.6, outerGap: 1, innerGap: 2)
      .withGaps(inner: 8, outer: 12)
    #expect(parameters == LayoutParameters(mainRatio: 0.6, outerGap: 12, innerGap: 8))
  }

  @Test func changingTheGapsKeepsTheRowWeights() {
    let parameters = LayoutParameters(rowWeights: [[], [2, 1]]).withGaps(inner: 4, outer: 4)
    #expect(parameters.rowWeights == [[], [2, 1]])
  }

  @Test(arguments: [0.0, -1, .infinity, .nan])
  func weightsThatCannotShareSpaceCountAsOne(weight: Double) {
    #expect(LayoutParameters(rowWeights: [[weight, 2]]).rowWeights == [[1, 2]])
  }

  @Test func settingTheRatioClamps() {
    var parameters = LayoutParameters()
    let didChange = parameters.setMainRatio(0.95)
    #expect(didChange)
    #expect(parameters.mainRatio == 0.9)
    let didChange2 = parameters.setMainRatio(0.9)
    #expect(!didChange2, "already there")
  }

  @Test func settingRowWeightsKeepsTheRowsFurtherDown() {
    var parameters = LayoutParameters(rowWeights: [[], [1, 2, 3]])
    parameters.setRowWeights([4, 5], inColumn: 1)
    parameters.setRowWeights([6], inColumn: 3)
    #expect(parameters.rowWeights == [[], [4, 5, 3], [], [6]])
  }

  @Test func rowWeightsArePaddedWithOnesAndCut() {
    let parameters = LayoutParameters(rowWeights: [[2], [3, 4, 5]])
    #expect(parameters.rowWeights(inColumn: 0, count: 3) == [2, 1, 1])
    #expect(parameters.rowWeights(inColumn: 1, count: 2) == [3, 4])
    #expect(parameters.rowWeights(inColumn: 7, count: 2) == [1, 1])
  }

  @Test func negativeGapsAreTreatedAsZero() {
    let parameters = LayoutParameters(outerGap: -4, innerGap: -2)
    #expect(parameters.outerGap == 0)
    #expect(parameters.innerGap == 0)
  }
}
