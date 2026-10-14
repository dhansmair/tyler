import CoreGraphics
import Testing

@testable import TylerCore

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
