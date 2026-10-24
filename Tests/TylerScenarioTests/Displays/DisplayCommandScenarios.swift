import CoreGraphics
import Testing
import TylerCore
import TylerTestSupport

@testable import TylerServer

/// The display commands. The laptop (`main`, display 1, workspaces 1 to 4) holds windows 1 and 2;
/// the external display above it (`secondary`, display 2, workspaces 5 to 8) holds windows 3 and 4
/// on workspace 5.
@Suite("Several displays: tyler display")
@MainActor
struct DisplayCommandScenarios {
  private func scenario() async -> Scenario {
    await Scenario(
      displays: [FakeDisplays.main, FakeDisplays.secondary], workspaces: [1: [1, 2], 5: [3, 4]])
  }

  @Test func aDisplayByNumberGetsTheFocusAndNothingMoves() async {
    let scenario = await scenario()
    await scenario.focus(4)
    await scenario.focus(1)
    scenario.windowSystem.clearRecordedCalls()
    #expect(await scenario.command("display focus 2") == .message("display 2"))
    #expect(scenario.focusedDisplay == 2)
    #expect(
      scenario.windowSystem.focusCalls == [WindowID(4)], "the window that last had focus there")
    #expect(scenario.windowSystem.moves.isEmpty)
  }

  @Test func prevAndNextWrap() async {
    let scenario = await scenario()
    await scenario.focus(1)
    #expect(await scenario.command("display focus next") == .message("display 2"))
    #expect(await scenario.command("display focus next") == .message("display 1"))
    #expect(await scenario.command("display focus prev") == .message("display 2"))
    #expect(scenario.focusedDisplay == 2)
  }

  @Test func theFocusedDisplayIsWhereTheNextCommandGoes() async {
    let scenario = await scenario()
    await scenario.focus(1)
    await scenario.command("display focus 2")
    #expect(await scenario.command("workspace focus next") == .message("workspace 6"))
    #expect(scenario.shown == [1, 6], "the laptop still shows 1")
  }

  @Test func onAnEmptyWorkspaceNoWindowKeepsTheFocus() async {
    let scenario = await Scenario(
      displays: [FakeDisplays.main, FakeDisplays.secondary], workspaces: [1: [1, 2], 5: [3, 4]],
      showing: [6])
    await scenario.focus(1)
    scenario.windowSystem.clearRecordedCalls()

    #expect(await scenario.command("display focus 2") == .message("display 2"))
    #expect(scenario.windowSystem.focusCalls.isEmpty)
    #expect(scenario.windowSystem.unfocusCount == 1, "keys don't go to the laptop's window")
    #expect(scenario.focusedDisplay == 2)
  }

  @Test func aNumberNoDisplayHasIsAnError() async {
    #expect(
      await scenario().command("display focus 3")
        == .error("display 3 does not exist (use 1 to 2)"))
  }

  @Test func withOneDisplayNextStaysOnIt() async {
    let scenario = await Scenario(workspaces: [1: [1]])
    await scenario.focus(1)
    #expect(await scenario.command("display focus next") == .message("display 1"))
    #expect(
      await scenario.command("display focus 2") == .error("display 2 does not exist (use 1)"))
  }

  @Test func itNeedsTilingOn() async {
    let scenario = await scenario()
    await scenario.command("tiling off")
    #expect(
      await scenario.command("display focus next") == .error(WindowManager.tilingOffMessage))
  }
}
