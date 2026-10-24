import Testing
import TylerCore
import TylerTestSupport

@testable import TylerServer

@Suite("Interaction")
@MainActor
struct InteractionTests {
  @Test func endingAKindThatIsNotRunningLeavesTheRunningOneAlone() async {
    let pointer = FakePointer()
    let harness = ManagerHarness([1, 2], pointer: pointer, clock: TestClock())
    pointer.swipe(.began)
    await harness.settle()
    harness.manager.endDrag()
    harness.manager.slide = nil
    #expect(harness.manager.swipe != nil)
  }
}
