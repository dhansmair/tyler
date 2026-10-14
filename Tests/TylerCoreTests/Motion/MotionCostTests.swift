import Testing

@testable import TylerCore

@Suite("MotionCost")
struct MotionCostTests {
  private func name(_ windowID: WindowID) -> String { "#\(windowID.rawValue)" }

  @Test func addsUpTheWritesAndKeepsTheSlowest() {
    var cost = MotionCost()
    cost.wrote(WindowID(1), taking: .milliseconds(2))
    cost.wrote(WindowID(2), taking: .milliseconds(9))
    cost.wrote(WindowID(3), taking: .milliseconds(1))
    #expect(cost.writes == 3)
    #expect(cost.writeTime == .milliseconds(12))
    #expect(
      cost.slowestWrite == MotionCost.Write(windowID: WindowID(2), duration: .milliseconds(9)))
  }

  @Test func theLongestGapIsBetweenFrameStarts() {
    var cost = MotionCost()
    for time in [9, 17, 38, 46] { cost.frameStarted(at: .milliseconds(time)) }
    #expect(cost.frames == 4)
    #expect(cost.firstFrame == .milliseconds(9))
    #expect(cost.longestFrameGap == .milliseconds(21))
  }

  @Test func theSummaryNamesTheSlowestWindow() {
    var cost = MotionCost()
    cost.frameStarted(at: .zero)
    cost.frameStarted(at: .milliseconds(21))
    cost.wrote(WindowID(812), taking: .microseconds(9_250))
    cost.windowUpdated()
    #expect(
      cost.summary(naming: name)
        == "2 frames (first after 0.0 ms, longest gap 21.0 ms), 1 writes in 9.3 ms, "
        + "slowest 9.3 ms #812, 1 updates")
  }

  @Test func queuedWritesAddUpAndNameTheSlowest() {
    var cost = MotionCost()
    var first = MotionCost.Queued()
    first.add(
      written: 3, skipped: 1, time: .milliseconds(6),
      slowest: MotionCost.Write(windowID: WindowID(1), duration: .milliseconds(4)))
    var second = MotionCost.Queued()
    second.add(
      written: 2, skipped: 0, time: .milliseconds(50),
      slowest: MotionCost.Write(windowID: WindowID(2), duration: .milliseconds(48)))
    cost.add(first)
    cost.add(second)
    #expect(cost.queued.written == 5)
    #expect(cost.queued.skipped == 1)
    #expect(
      cost.summary(naming: name)
        == "0 writes in 0.0 ms, queued 5 in 56.0 ms, 1 skipped, slowest 48.0 ms #2, 0 updates")
  }

  @Test func aCostWithoutFramesOrWritesSaysSo() {
    #expect(MotionCost().summary(naming: name) == "0 writes in 0.0 ms, 0 updates")
  }
}
