import CoreGraphics
import Testing
import TylerConfig
import TylerCore
import TylerTestSupport

/// Moving a whole workspace to another display. The laptop (`main`, display 1, workspaces 1 to 4)
/// holds windows 1 and 2 on workspace 1 and window 9 parked on workspace 2; the external display
/// above it (`secondary`, display 2, workspaces 5 to 8) holds windows 3 and 4 on workspace 5.
@Suite("Several displays: tyler workspace move-to-display")
@MainActor
struct MoveWorkspaceToDisplayScenarios {
  private let displays = [FakeDisplays.main, FakeDisplays.secondary]

  private func scenario(config: Config = Config()) async -> Scenario {
    let scenario = await Scenario(
      displays: displays, workspaces: [1: [1, 2], 2: [9], 5: [3, 4]], config: config)
    await scenario.focus(1)
    scenario.windowSystem.clearRecordedCalls()
    return scenario
  }

  @Test func theWorkspaceComesOnScreenThereWithItsWindowsAndTheFocus() async {
    let scenario = await scenario()
    #expect(
      await scenario.command("workspace move-to-display 2")
        == .message("moved workspace 1 to display 2"))
    #expect(scenario.rows == [[2, 3, 4], [1, 5, 6, 7, 8]])
    #expect(scenario.shown == [2, 1])
    #expect(
      scenario.workspaces == [1: 1, 2: 1, 3: 5, 4: 5, 9: 2], "every window kept its workspace")
    #expect(scenario.frame(of: 1) == scenario.rect(.leftHalf, display: 2))
    #expect(scenario.frame(of: 2) == scenario.rect(.rightHalf, display: 2))
    #expect(scenario.isParked(3))
    #expect(scenario.isParked(4))
    #expect(scenario.focusedDisplay == 2)
    #expect(scenario.windowSystem.focusCalls.last == WindowID(1))
  }

  @Test func theDisplayItLeftShowsItsNextWorkspace() async {
    let scenario = await scenario()
    await scenario.command("workspace move-to-display next")
    #expect(scenario.frame(of: 9) == scenario.rect(.full))
  }

  @Test func itStaysOnItsNewDisplayThroughUnpluggingAndPluggingBackIn() async {
    let scenario = await scenario()
    await scenario.command("workspace move-to-display 2")

    await scenario.changeDisplays(to: [FakeDisplays.main])
    #expect(scenario.rows == [[1, 2, 3, 4, 5, 6, 7, 8]])
    await scenario.changeDisplays(to: displays)
    #expect(scenario.rows == [[2, 3, 4], [1, 5, 6, 7, 8]])
    #expect(scenario.shown == [2, 1])
    #expect(scenario.frame(of: 1) == scenario.rect(.leftHalf, display: 2))
  }

  @Test func aRestartKeepsItsNewHome() async {
    let scenario = await scenario()
    await scenario.command("workspace move-to-display 2")
    let next = await scenario.restart()
    #expect(next.rows == [[2, 3, 4], [1, 5, 6, 7, 8]])
    await next.changeDisplays(to: [FakeDisplays.main])
    await next.changeDisplays(to: displays)
    #expect(next.rows == [[2, 3, 4], [1, 5, 6, 7, 8]], "its home is still display 2")
  }

  /// A window on its way to another display keeps its workspace until it arrives; one whose app
  /// refused the move belongs where it stayed from the next command on.
  @Test func aWindowWhoseAppRefusedTheMoveStaysBehindAtTheNextCommand() async {
    let scenario = await scenario()
    scenario.windowSystem.failingMoves = [WindowID(2)]
    #expect(
      await scenario.command("workspace move-to-display 2")
        == .message("moved workspace 1 to display 2; 1 window could not be placed"))
    #expect(scenario.workspaces[2] == 1, "held while it might still arrive")

    await scenario.command("workspace retile")
    #expect(scenario.workspaces[2] == 2, "it joins the laptop's workspace on screen")
  }

  @Test func aWorkspaceAlreadyThereIsRefused() async {
    let scenario = await scenario()
    #expect(
      await scenario.command("workspace move-to-display 1")
        == .error("workspace 1 is already on display 1"))
    #expect(scenario.windowSystem.moves.isEmpty)
  }

  @Test func theOnlyWorkspaceOfADisplayCannotLeaveIt() async {
    let scenario = await Scenario(
      displays: displays, workspaces: [1: [1, 2]],
      config: Config(workspaces: Config.Workspaces(count: 1)))
    await scenario.focus(1)
    scenario.windowSystem.clearRecordedCalls()
    #expect(
      await scenario.command("workspace move-to-display next")
        == .error("workspace 1 is the only one on its display"))
    #expect(scenario.windowSystem.moves.isEmpty)
  }

  @Test func aNumberNoDisplayHasIsAnError() async {
    #expect(
      await scenario().command("workspace move-to-display 3")
        == .error("display 3 does not exist (use 1 to 2)"))
  }
}
