import CoreGraphics
import Testing

@testable import TylerCore

@Suite("LayoutKind and layout state")
struct LayoutKindTests {
  @Test(arguments: [
    (LayoutKind.tall, [LayoutKind.tall, .full, .strip], LayoutKind.full),
    (.strip, [.tall, .full, .strip], .tall),
    (.full, LayoutKind.defaultCycle, .tall),
    (.strip, LayoutKind.defaultCycle, .tall),  // not in the cycle: its first
    (.full, [.full], .full),
    (.full, [], .full),
  ])
  func nextFollowsTheCycleAndWraps(layout: LayoutKind, cycle: [LayoutKind], next: LayoutKind) {
    #expect(layout.next(in: cycle) == next)
  }

  @Test func theDefaultCycleLeavesOutTheExperimentalStrip() {
    #expect(LayoutKind.defaultCycle == [.tall, .full])
  }

  @Test(arguments: LayoutKind.allCases)
  func everyKindProducesALayout(kind: LayoutKind) {
    let frames = kind.bound.frames(
      of: ids(1, 2), states: LayoutStates(), view: 0,
      in: CGRect(x: 0, y: 0, width: 100, height: 100), gaps: LayoutGaps())
    #expect(frames.count == 2)
  }

  @Test func ratioIsClampedOnCreation() {
    #expect(TallLayoutState(mainRatio: 0.0).mainRatio == 0.1)
    #expect(TallLayoutState(mainRatio: 5).mainRatio == 0.9)
  }

  @Test func adjustingTheRatioStaysInRangeAndReportsChange() {
    var state = TallLayoutState(mainRatio: 0.85)
    let didChange = state.adjustRatio(by: 0.05)
    #expect(didChange)
    #expect(state.mainRatio == 0.9)
    let didChange2 = state.adjustRatio(by: 0.05)
    #expect(!didChange2, "already at the limit")
    #expect(state.mainRatio == 0.9)
  }

  @Test func repeatedStepsDoNotAccumulateFloatingPointNoise() {
    var state = TallLayoutState(mainRatio: 0.5)
    for _ in 0..<7 { state.adjustRatio(by: 0.05) }
    for _ in 0..<7 { state.adjustRatio(by: -0.05) }
    #expect(state.mainRatio == 0.5)
  }

  @Test(arguments: [0.0, -1, .infinity, .nan])
  func weightsThatCannotShareSpaceCountAsOne(weight: Double) {
    #expect(TallLayoutState(rowWeights: [[weight, 2]]).rowWeights == [[1, 2]])
  }

  @Test func settingTheRatioClamps() {
    var state = TallLayoutState()
    let didChange = state.setMainRatio(0.95)
    #expect(didChange)
    #expect(state.mainRatio == 0.9)
    let didChange2 = state.setMainRatio(0.9)
    #expect(!didChange2, "already there")
  }

  @Test func settingRowWeightsKeepsTheRowsFurtherDown() {
    var state = TallLayoutState(rowWeights: [[], [1, 2, 3]])
    state.setRowWeights([4, 5], inColumn: 1)
    state.setRowWeights([6], inColumn: 3)
    #expect(state.rowWeights == [[], [4, 5, 3], [], [6]])
  }

  @Test func rowWeightsArePaddedWithOnesAndCut() {
    let state = TallLayoutState(rowWeights: [[2], [3, 4, 5]])
    #expect(state.rowWeights(inColumn: 0, count: 3) == [2, 1, 1])
    #expect(state.rowWeights(inColumn: 1, count: 2) == [3, 4])
    #expect(state.rowWeights(inColumn: 7, count: 2) == [1, 1])
  }

  @Test func negativeGapsAreTreatedAsZero() {
    let gaps = LayoutGaps(inner: -2, outer: -4)
    #expect(gaps.outer == 0)
    #expect(gaps.inner == 0)
  }
}
