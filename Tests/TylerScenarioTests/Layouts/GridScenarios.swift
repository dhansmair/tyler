import Testing
import TylerTestSupport

@Suite("The grid layout")
@MainActor
struct GridScenarios {
  @Test func theGridHasNoRatio() async {
    let scenario = await Scenario(workspaces: [1: [1, 2, 3, 4]], layout: .grid)
    scenario.windowSystem.clearRecordedCalls()
    #expect(await scenario.command("layout ratio +0.1") == .message("grid has no master ratio"))
    #expect(scenario.windowSystem.moves.isEmpty)
    await scenario.command("layout set tall")
    #expect(scenario.frame(of: 1) == scenario.rect(.leftHalf), "tall's ratio is unchanged")
  }
}
