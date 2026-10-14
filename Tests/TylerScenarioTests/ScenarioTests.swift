import Testing
import TylerTestSupport

/// The context a `Scenario` sets up is the one tylerd starts from.
@Suite("Scenario setup")
@MainActor
struct ScenarioTests {
  @Test func eachWorkspaceHoldsItsWindowsInOrder() async {
    let scenario = await Scenario(workspaces: [1: [2, 1], 2: [3]])
    #expect(scenario.list(1) == [2, 1])
    #expect(scenario.list(2) == [3])
  }

  @Test func eachDisplayShowsItsFirstWorkspaceAndParksTheRest() async {
    let scenario = await Scenario(workspaces: [1: [1], 2: [2]])
    #expect(scenario.shown == [1])
    #expect(scenario.frame(of: 1) == scenario.rect(.full))
    #expect(scenario.isParked(2))
  }

  @Test func theWorkspacesShowingAreOnScreen() async {
    let scenario = await Scenario(workspaces: [1: [1], 2: [2]], showing: [2])
    #expect(scenario.shown == [2])
    #expect(scenario.frame(of: 2) == scenario.rect(.full))
    #expect(scenario.isParked(1))
  }

  @Test func aSecondDisplayHasWorkspacesFromFive() async {
    let scenario = await Scenario(
      displays: [FakeDisplays.main, FakeDisplays.right], workspaces: [1: [1], 5: [2]])
    #expect(scenario.shown == [1, 5])
    #expect(scenario.frame(of: 2) == scenario.rect(.full, display: 2))
  }

  @Test func theLayoutIsEveryWorkspaces() async {
    let scenario = await Scenario(workspaces: [1: [1, 2], 2: [3, 4]], layout: .full)
    #expect(scenario.frame(of: 1) == scenario.rect(.full))
    #expect(scenario.frame(of: 2) == scenario.rect(.full))
    await scenario.command("workspace focus 2")
    #expect(scenario.frame(of: 4) == scenario.rect(.full))
  }
}
