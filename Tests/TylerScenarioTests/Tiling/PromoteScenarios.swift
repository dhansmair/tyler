import Testing
import TylerCore
import TylerProtocol
import TylerTestSupport

@testable import TylerServer

/// `window promote` and `window demote`: windows moving between tall's master section and its
/// stack.
@Suite("Tiling: promote and demote")
@MainActor
struct PromoteScenarios {
  @Test func aPromotedWindowJoinsTheMainOnTheLeft() async {
    let scenario = await Scenario(workspaces: [1: [1, 2, 3]])
    await scenario.focus(3)
    #expect(await scenario.command("window promote") == .ok)
    #expect(scenario.list(1) == [1, 3, 2])
    #expect(scenario.frame(of: 1) == scenario.rect(.leftTop))
    #expect(scenario.frame(of: 3) == scenario.rect(.leftBottom))
    #expect(scenario.frame(of: 2) == scenario.rect(.rightHalf))
  }

  @Test func demotingItAgainRestoresTheLayout() async {
    let scenario = await Scenario(workspaces: [1: [1, 2, 3]])
    await scenario.focus(3)
    await scenario.command("window promote")
    #expect(await scenario.command("window demote") == .ok)
    #expect(scenario.list(1) == [1, 3, 2])
    #expect(scenario.frame(of: 1) == scenario.rect(.leftHalf))
    #expect(scenario.frame(of: 3) == scenario.rect(.rightTop))
    #expect(scenario.frame(of: 2) == scenario.rect(.rightBottom))
  }

  @Test func promotingTheLastStackedWindowGivesOneColumn() async {
    let scenario = await Scenario(workspaces: [1: [1, 2]])
    await scenario.focus(2)
    await scenario.command("window promote")
    #expect(scenario.frame(of: 1) == scenario.rect(.top))
    #expect(scenario.frame(of: 2) == scenario.rect(.bottom))
  }

  @Test func demotingTheOnlyMainHandsItsPlaceOn() async {
    let scenario = await Scenario(workspaces: [1: [1, 2, 3]])
    await scenario.focus(1)
    #expect(await scenario.command("window demote") == .ok)
    #expect(scenario.list(1) == [2, 1, 3])
    #expect(scenario.frame(of: 2) == scenario.rect(.leftHalf))
  }

  @Test func aWindowAlreadyThereStaysAndTylerSaysSo() async {
    let scenario = await Scenario(workspaces: [1: [1, 2, 3]])
    await scenario.focus(1)
    #expect(await scenario.command("window promote") == .message("already in the master section"))
    await scenario.focus(2)
    #expect(await scenario.command("window demote") == .message("already in the stack"))
    #expect(scenario.list(1) == [1, 2, 3])
  }

  @Test func outsideTallThereIsNoMainSection() async {
    let scenario = await Scenario(workspaces: [1: [1, 2, 3]], layout: .grid)
    await scenario.focus(2)
    #expect(
      await scenario.command("window promote")
        == .error("only the tall layout has a master section"))
    #expect(scenario.list(1) == [1, 2, 3])
  }

  @Test func aNewWindowOpensInTheStackWhileAMainHasFocus() async {
    let scenario = await Scenario(workspaces: [1: [1, 2, 3]])
    await scenario.focus(2)
    await scenario.command("window promote")
    scenario.harness.windowSystem.windows.append(makeWindow(id: 4))
    scenario.harness.windowSystem.send(.created(makeWindow(id: 4)))
    await scenario.runUntilQuiet()
    #expect(scenario.list(1) == [1, 2, 4, 3])
    #expect(scenario.frame(of: 2) == scenario.rect(.leftBottom))
    #expect(scenario.frame(of: 4) == scenario.rect(.rightTop))
  }

  @Test func closingAMainShrinksTheMainSection() async {
    let scenario = await Scenario(workspaces: [1: [1, 2, 3]])
    await scenario.focus(2)
    await scenario.command("window promote")
    await scenario.command("window close")
    scenario.harness.windowSystem.send(.destroyed(WindowID(2)))
    await scenario.runUntilQuiet()
    #expect(scenario.list(1) == [1, 3])
    #expect(scenario.frame(of: 1) == scenario.rect(.leftHalf))
    #expect(scenario.frame(of: 3) == scenario.rect(.rightHalf))
  }
}
