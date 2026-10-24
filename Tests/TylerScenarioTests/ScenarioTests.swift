import Testing
import TylerConfig
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

  @Test func windowsOpenAtAFirstStartAreTiledOnTheFirstWorkspace() async {
    let scenario = await Scenario(openAtStart: spread([1, 2]))
    #expect(scenario.list(1) == [1, 2])
    #expect(scenario.frame(of: 1) == scenario.rect(.leftHalf))
  }

  @Test func withoutPermissionNothingIsTiled() async {
    let scenario = await Scenario(openAtStart: spread([1]), gate: FakeGate(isTrusted: false))
    #expect(scenario.workspaces.isEmpty)
  }

  @Test func anOpenedWindowJoinsTheList() async {
    let scenario = await Scenario(workspaces: [1: [1]])
    await scenario.open(makeWindow(id: 2))
    #expect(scenario.list(1) == [1, 2])
  }

  @Test func aClosedWindowLeavesTheList() async {
    let scenario = await Scenario(workspaces: [1: [1, 2]])
    await scenario.close(1)
    #expect(scenario.list(1) == [2])
    #expect(scenario.frame(of: 1) == nil)
  }

  @Test func aChangedWindowIsWhatMacOSReports() async {
    let scenario = await Scenario(workspaces: [1: [1, 2]])
    await scenario.change(makeWindow(id: 2, isMinimized: true))
    #expect(scenario.list(1) == [1])
    #expect(scenario.windowSystem.windows.first { $0.id.rawValue == 2 }?.isMinimized == true)
  }

  @Test func aReloadReadsTheConfigFile() async {
    let file = FakeConfigFile()
    let scenario = await Scenario(workspaces: [1: [1]], configFile: file)
    file.write(.config(Config(workspaces: Config.Workspaces(count: 6))))
    await scenario.command("config reload")
    #expect(await scenario.command("workspace focus 6") == .message("workspace 6"))
  }

  @Test func theNextTylerdCarriesOnWithTheWorkspaces() async {
    let scenario = await Scenario(workspaces: [1: [1, 2], 2: [3]], showing: [2])
    let next = await scenario.restart()
    #expect(next.shown == [2])
    #expect(next.list(1) == [1, 2])
    #expect(next.list(2) == [3])
    #expect(next.isParked(1))
  }
}
