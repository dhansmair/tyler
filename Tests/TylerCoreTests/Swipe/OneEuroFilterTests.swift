import Testing

@testable import TylerCore

@Suite("OneEuroFilter")
struct OneEuroFilterTests {
  private let filter = OneEuroFilter(minimumCutoff: 2, speedCoefficient: 20)

  @Test func theFirstValuePassesThrough() {
    var filter = filter
    #expect(filter.filter(0.3, at: 1) == 0.3)
  }

  @Test func aValueWithoutTimePassingChangesNothing() {
    var filter = filter
    _ = filter.filter(0.3, at: 1)
    #expect(filter.filter(0.9, at: 1) == 0.3)
  }

  @Test func noiseAroundAStillValueIsDamped() {
    var filter = filter
    _ = filter.filter(0, at: 0)
    var largest = 0.0
    for step in 1...100 {
      let noise = step.isMultiple(of: 2) ? 0.01 : -0.01
      largest = max(largest, abs(filter.filter(noise, at: Double(step) * 0.01)))
    }
    #expect(largest < 0.005, "less than half the noise gets through")
  }

  @Test func aFastMotionIsFollowedClosely() {
    var filter = filter
    var smoothed = 0.0
    // 1.5 units per second for 0.2 s, at 100 frames a second.
    for step in 0...20 {
      smoothed = filter.filter(Double(step) * 0.015, at: Double(step) * 0.01)
    }
    #expect(abs(smoothed - 0.3) < 0.03, "within a tenth of the way travelled")
  }
}
