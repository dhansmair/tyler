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

  @Test func aTinyAreaDoesNotProduceNegativeSizes() {
    for rect in frames(5, in: CGRect(x: 0, y: 0, width: 10, height: 10)) {
      #expect(rect.width >= 0)
      #expect(rect.height >= 0)
    }
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

  @Test func negativeGapsAreTreatedAsZero() {
    let parameters = LayoutParameters(outerGap: -4, innerGap: -2)
    #expect(parameters.outerGap == 0)
    #expect(parameters.innerGap == 0)
  }
}
