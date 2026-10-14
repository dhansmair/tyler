import Testing
import TylerTestSupport

@testable import TylerServer

@Suite("The grid layout")
@MainActor
struct GridScenarios {
  @Test func theGridHasNoRatio() {
    let harness = ManagerHarness([1, 2, 3, 4])
    _ = harness.manager.setLayout(.set(.grid))
    harness.windowSystem.clearRecordedCalls()
    #expect(harness.manager.adjustRatio(by: 0.1) == .message("grid has no master ratio"))
    #expect(harness.windowSystem.moves.isEmpty)
    #expect(harness.manager.workspaces.current.layoutStates.tall.mainRatio == 0.5)
  }
}
