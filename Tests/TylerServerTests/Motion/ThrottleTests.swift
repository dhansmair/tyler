import Testing
import TylerTestSupport

@testable import TylerServer

@Suite("Throttle")
@MainActor
struct ThrottleTests {
  private let clock = TestClock()

  @Test func theStepRunsOnceTheIntervalIsUp() async {
    var throttle = Throttle()
    var runs = 0
    throttle.hold(for: .milliseconds(50), on: clock) { runs += 1 }
    #expect(throttle.isHolding)
    await settle()  // the wait starts
    clock.advance(by: .milliseconds(49))
    await settle()
    #expect(runs == 0)
    clock.advance(by: .milliseconds(1))
    await settle()
    #expect(runs == 1)
  }

  @Test func withoutAnIntervalNothingIsHeldBack() {
    var throttle = Throttle()
    throttle.hold(for: .zero, on: clock) {}
    #expect(!throttle.isHolding)
  }

  @Test func releasingDropsTheWaitingStep() async {
    var throttle = Throttle()
    var runs = 0
    throttle.hold(for: .milliseconds(50), on: clock) { runs += 1 }
    await settle()
    throttle.release()
    #expect(!throttle.isHolding)
    clock.advance(by: .milliseconds(50))
    await settle()
    #expect(runs == 0)
  }
}
