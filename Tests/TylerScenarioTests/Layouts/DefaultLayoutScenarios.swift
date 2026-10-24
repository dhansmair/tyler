import CoreGraphics
import Testing
import TylerConfig
import TylerCore
import TylerTestSupport

@Suite("Layouts: the default of new workspaces")
@MainActor
struct DefaultLayoutScenarios {
  private func config(_ initial: LayoutKind, count: Int = 4) -> Config {
    Config(
      layouts: Config.Layouts(initial: initial), workspaces: Config.Workspaces(count: count))
  }

  private func layouts(_ scenario: Scenario, count: Int = 4) -> [LayoutKind?] {
    (1...count).map(scenario.layout)
  }

  @Test func everyWorkspaceStartsWithTheDefault() async {
    let scenario = await Scenario(openAtStart: spread([1, 2]), config: config(.full))
    #expect(layouts(scenario) == [.full, .full, .full, .full])
    #expect(scenario.frame(of: 1) == scenario.rect(.full))
    #expect(scenario.frame(of: 2) == scenario.rect(.full))
  }

  @Test func withoutAConfigWorkspacesStartTall() async {
    #expect(layouts(await Scenario(openAtStart: spread([1]))) == [.tall, .tall, .tall, .tall])
  }

  @Test func workspacesAddedByReloadGetTheNewDefault() async {
    let file = FakeConfigFile()
    let scenario = await Scenario(openAtStart: spread([1]), configFile: file)
    await scenario.command("layout set full")
    file.write(.config(config(.strip, count: 5)))
    await scenario.command("config reload")
    // Workspaces that existed keep their layout; only the new one gets the new default.
    #expect(layouts(scenario, count: 5) == [.full, .tall, .tall, .tall, .strip])
  }

  @Test func aRestartKeepsEachWorkspacesLayout() async {
    let scenario = await Scenario(openAtStart: spread([1]), config: config(.full))
    await scenario.command("layout set tall")
    let next = await scenario.restart(config: config(.strip))
    #expect(layouts(next) == [.tall, .full, .full, .full])
  }
}
