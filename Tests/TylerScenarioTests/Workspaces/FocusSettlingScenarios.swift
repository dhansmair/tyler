import Testing
import TylerCore
import TylerTestSupport

@testable import TylerServer

/// An app with windows on two displays can focus the one it remembers on its way to the one asked
/// for, so a focus on a parked window only brings its workspace into view once it has lasted
/// (#87).
@Suite("Workspaces: focus settling on a parked window")
@MainActor
struct FocusSettlingScenarios {
  private func twoDisplays() async -> Scenario {
    await Scenario(
      displays: [FakeDisplays.main, FakeDisplays.secondary],
      workspaces: [1: [1], 2: [2], 5: [3], 6: [4]])
  }

  @Test func aPassingFocusOnAParkedWindowSwitchesNothing() async {
    let scenario = await twoDisplays()
    await scenario.focusInTurn(2, 3)
    #expect(scenario.shown == [1, 5])
  }

  @Test func aPassingFocusAfterTheWantedWindowSwitchesNothing() async {
    let scenario = await twoDisplays()
    await scenario.focusInTurn(3, 2, 3)
    #expect(scenario.shown == [1, 5])
  }

  @Test func aFocusThatLastsBringsItsWorkspaceIntoView() async {
    let scenario = await twoDisplays()
    scenario.harness.windowSystem.send(.focused(WindowID(2)))
    await scenario.wait(WorkspaceController.parkedFocusSettling - .milliseconds(1))
    #expect(scenario.shown == [1, 5])
    await scenario.wait(.milliseconds(1))
    await scenario.runUntilQuiet()
    #expect(scenario.shown == [2, 5])
  }

  @Test func theLastOfSeveralParkedWindowsCounts() async {
    let scenario = await twoDisplays()
    await scenario.focusInTurn(2, 4)
    #expect(scenario.shown == [1, 6])
  }

  @Test func aCommandWhileAFocusSettlesWins() async {
    let scenario = await twoDisplays()
    scenario.harness.windowSystem.send(.focused(WindowID(2)))
    await scenario.harness.settle()
    await scenario.command("workspace focus 3")
    #expect(scenario.shown == [3, 5])
  }

  @Test func aWindowClosedWhileItsFocusSettlesSwitchesNothing() async {
    let scenario = await twoDisplays()
    scenario.harness.windowSystem.send(.focused(WindowID(2)))
    await scenario.close(2)
    #expect(scenario.shown == [1, 5])
  }
}
