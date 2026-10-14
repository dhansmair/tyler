import Testing
import TylerTestSupport

@testable import TylerServer

@Suite("Debounce")
@MainActor
struct DebounceTests {
  private let clock = TestClock()

  @Test func theActionRunsOnceTheQuietHasLasted() async {
    let debounce = Debounce(clock: clock)
    var runs = 0
    debounce.restart(after: .milliseconds(50)) { runs += 1 }
    #expect(debounce.isPending)
    await settle()  // the wait starts
    clock.advance(by: .milliseconds(49))
    await settle()
    #expect(runs == 0)
    clock.advance(by: .milliseconds(1))
    await settle()
    #expect(runs == 1)
    #expect(!debounce.isPending)
  }

  @Test func onlyTheLastRestartActs() async {
    let debounce = Debounce(clock: clock)
    var acted: [Int] = []
    debounce.restart(after: .milliseconds(50)) { acted.append(1) }
    await settle()
    clock.advance(by: .milliseconds(30))
    await settle()
    debounce.restart(after: .milliseconds(50)) { acted.append(2) }
    await settle()
    clock.advance(by: .milliseconds(30))
    await settle()
    #expect(acted.isEmpty, "the wait started again")
    clock.advance(by: .milliseconds(20))
    await settle()
    #expect(acted == [2])
  }

  @Test func cancellingDropsTheWaitingAction() async {
    let debounce = Debounce(clock: clock)
    var runs = 0
    debounce.restart(after: .milliseconds(50)) { runs += 1 }
    await settle()
    debounce.cancel()
    #expect(!debounce.isPending)
    clock.advance(by: .milliseconds(50))
    await settle()
    #expect(runs == 0)
  }
}
