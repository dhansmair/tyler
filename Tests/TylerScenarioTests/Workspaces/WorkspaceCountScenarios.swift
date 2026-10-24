import CoreGraphics
import Testing
import TylerConfig
import TylerCore
import TylerTestSupport

@Suite("Workspaces: the configured count")
@MainActor
struct WorkspaceCountScenarios {
  private func config(count: Int) -> Config {
    Config(workspaces: Config.Workspaces(count: count))
  }

  @Test func theCountComesFromTheConfig() async {
    let scenario = await Scenario(workspaces: [1: [1]], config: config(count: 6))
    #expect(await scenario.command("workspace focus 6") == .message("workspace 6"))
    #expect(
      await scenario.command("workspace focus 7")
        == .error("workspace 7 does not exist (use 1 to 6)"))
  }

  @Test func theLaptopsWorkspacesComeFromDisplays() async {
    let scenario = await Scenario(
      openAtStart: spread([1]), config: Config(displays: [1: [3, 4, 9]]))
    #expect(await scenario.command("workspace focus 9") == .message("workspace 9"))
    #expect(
      await scenario.command("workspace focus 1")
        == .error("workspace 1 does not exist (use 3, 4, 9)"))
    #expect(scenario.workspaces == [1: 3], "windows start on the first")
  }

  @Test func reloadRenumbersFromDisplaysAndKeepsTheWindows() async {
    let file = FakeConfigFile()
    let scenario = await Scenario(workspaces: [1: [1], 2: [2]], configFile: file)
    file.write(.config(Config(displays: [1: [1, 5]])))

    #expect(await scenario.command("config reload") == .message("reloaded \(FakeConfigFile.path)"))
    #expect(scenario.workspaces == [1: 1, 2: 5], "workspace 2's window joined the last")
    #expect(await scenario.command("workspace focus 5") == .message("workspace 5"))
  }

  @Test func reloadAddsWorkspaces() async {
    let file = FakeConfigFile()
    let scenario = await Scenario(workspaces: [1: [1]], configFile: file)
    file.write(.config(config(count: 6)))

    #expect(await scenario.command("config reload") == .message("reloaded \(FakeConfigFile.path)"))
    #expect(await scenario.command("workspace focus 6") == .message("workspace 6"))
  }

  @Test func reloadMergesRemovedWorkspacesIntoTheLastAndBringsThemIntoView() async {
    let file = FakeConfigFile()
    let scenario = await Scenario(
      workspaces: [1: [1], 2: [2], 4: [3]], showing: [2], configFile: file)
    #expect(scenario.isParked(3))

    file.write(.config(config(count: 2)))
    #expect(await scenario.command("config reload") == .message("reloaded \(FakeConfigFile.path)"))
    #expect(scenario.workspaces == [1: 1, 2: 2, 3: 2])
    #expect(!scenario.isParked(3), "the merged window joined the workspace on screen")
    #expect(scenario.isParked(1), "workspace 1 is still parked")
    #expect(
      [scenario.frame(of: 2), scenario.frame(of: 3)]
        == [scenario.rect(.leftHalf), scenario.rect(.rightHalf)])
  }

  @Test func reloadRemovingTheCurrentWorkspaceShowsTheNewLastOne() async {
    let file = FakeConfigFile()
    let scenario = await Scenario(workspaces: [1: [1], 4: [2]], showing: [4], configFile: file)

    file.write(.config(config(count: 1)))
    await scenario.command("config reload")
    #expect(scenario.workspaces == [1: 1, 2: 1])
    #expect(!scenario.isParked(1))
    #expect(!scenario.isParked(2))
    #expect(await scenario.command("workspace focus next") == .message("workspace 1"))
  }

  @Test func aRestartWithFewerWorkspacesShowsTheMergedWindows() async {
    let scenario = await Scenario(workspaces: [1: [1], 3: [2]])
    #expect(scenario.isParked(2))

    let next = await scenario.restart(config: config(count: 1))
    #expect(
      [next.frame(of: 1), next.frame(of: 2)] == [next.rect(.leftHalf), next.rect(.rightHalf)],
      "window 2 was merged into workspace 1, the one on screen, and came out of parking")
  }
}
