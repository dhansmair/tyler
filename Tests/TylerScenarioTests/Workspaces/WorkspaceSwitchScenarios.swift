import CoreGraphics
import Testing
import TylerCore
import TylerTestSupport

@testable import TylerServer

@Suite("Workspaces: switching")
@MainActor
struct WorkspaceSwitchScenarios {
  @Test func existingWindowsStartOnTheFirstWorkspace() async {
    let scenario = await Scenario(openAtStart: spread([1, 2]))
    #expect(scenario.workspaces == [1: 1, 2: 1])
  }

  @Test func switchingParksTheCurrentWindowsAndGivesNoFocusToAnEmptyWorkspace() async {
    let scenario = await Scenario(workspaces: [1: [1, 2]])
    scenario.windowSystem.clearRecordedCalls()
    #expect(await scenario.command("workspace focus next") == .message("workspace 2"))
    #expect(scenario.isParked(1))
    #expect(scenario.isParked(2))
    #expect(scenario.workspaces == [1: 1, 2: 1], "parked windows keep their workspace")
    #expect(scenario.windowSystem.focusCalls.isEmpty)
    #expect(scenario.windowSystem.unfocusCount == 0, "no window had focus")
  }

  @Test func switchingToAnEmptyWorkspaceTakesFocusFromTheParkedWindow() async {
    let scenario = await Scenario(workspaces: [1: [1, 2]])
    await scenario.focus(2)
    scenario.windowSystem.clearRecordedCalls()
    await scenario.command("workspace focus next")
    #expect(scenario.isParked(2))
    #expect(scenario.windowSystem.focusCalls.isEmpty)
    #expect(scenario.windowSystem.unfocusCount == 1)
  }

  @Test func failingToTakeFocusStillSwitchesAndSaysSo() async {
    let scenario = await Scenario(workspaces: [1: [1]])
    await scenario.focus(1)
    scenario.windowSystem.clearRecordedCalls()
    scenario.windowSystem.isUnfocusFailing = true
    #expect(
      await scenario.command("workspace focus next")
        == .message("workspace 2; cannot take focus from window 1: fake refusal"))
    #expect(scenario.isParked(1))
    #expect(scenario.windowSystem.unfocusCount == 1)
  }

  @Test func aWindowThatRefusesFocusIsReportedAfterTheSwitch() async {
    let scenario = await Scenario(workspaces: [1: [1], 2: [2]])
    scenario.windowSystem.failingFocus = [WindowID(2)]
    #expect(
      await scenario.command("workspace focus next")
        == .message("workspace 2; cannot focus window 2: fake refusal"))
    #expect(scenario.shown == [2])
  }

  @Test func newWindowsOpenOnTheCurrentWorkspace() async {
    let scenario = await Scenario(workspaces: [1: [1, 2]], showing: [3])
    await scenario.open(makeWindow(id: 9))
    #expect(scenario.workspaces == [1: 1, 2: 1, 9: 3])
    #expect(scenario.frame(of: 9) == scenario.rect(.full))
  }

  @Test func switchingBackRestoresTheSlotsAndFocusesTheFocusedWindow() async {
    let scenario = await Scenario(workspaces: [1: [1, 2]])
    let slots = [scenario.frame(of: 1), scenario.frame(of: 2)]
    await scenario.focus(2)
    scenario.windowSystem.clearRecordedCalls()
    await scenario.command("workspace focus next")
    await scenario.command("workspace focus prev")
    #expect([scenario.frame(of: 1), scenario.frame(of: 2)] == slots)
    #expect(scenario.windowSystem.focusCalls == [WindowID(2)])
  }

  @Test(arguments: [
    ("next", 4, "workspace 1"), ("prev", 1, "workspace 4"), ("2", 1, "workspace 2"),
  ])
  func nextAndPrevWrapAtTheEnds(target: String, from: Int, expected: String) async {
    let scenario = await Scenario(workspaces: [1: [1]], showing: [from])
    #expect(await scenario.command("workspace focus \(target)") == .message(expected))
  }

  @Test func aWorkspaceOutOfRangeIsAnError() async {
    let scenario = await Scenario(workspaces: [1: [1]])
    scenario.windowSystem.clearRecordedCalls()
    #expect(
      await scenario.command("workspace focus 5")
        == .error("workspace 5 does not exist (use 1 to 4)"))
    #expect(scenario.windowSystem.moves.isEmpty)
  }

  @Test func switchingToTheCurrentWorkspaceMovesNothing() async {
    let scenario = await Scenario(workspaces: [1: [1, 2]])
    scenario.windowSystem.clearRecordedCalls()
    #expect(await scenario.command("workspace focus 1") == .message("workspace 1"))
    #expect(scenario.windowSystem.moves.isEmpty)
  }

  @Test func switchingNeedsTiling() async {
    let scenario = await Scenario(workspaces: [1: [1]])
    await scenario.command("tiling off")
    #expect(
      await scenario.command("workspace focus next") == .error(WindowManager.tilingOffMessage))
    #expect(
      await scenario.command("window move-to-workspace next")
        == .error(WindowManager.tilingOffMessage))
  }

  @Test func switchingNeedsPermission() async {
    let scenario = await Scenario(workspaces: [:], gate: FakeGate(isTrusted: false))
    #expect(
      await scenario.command("workspace focus next") == .error(WindowManager.permissionMessage))
  }

  @Test func aWindowSentToAnotherWorkspaceIsThereWhenItIsShown() async {
    let scenario = await Scenario(workspaces: [1: [1, 2]])
    await scenario.focus(2)
    #expect(
      await scenario.command("window move-to-workspace 3") == .message("moved to workspace 3"))
    #expect(await scenario.command("workspace focus 3") == .message("workspace 3"))
    #expect(scenario.workspaces == [1: 1, 2: 3])
  }

  @Test func tilingOffBringsParkedWindowsBackAndForgetsTheirWorkspace() async {
    let scenario = await Scenario(openAtStart: spread([1, 2, 3]))
    await scenario.command("workspace focus next")
    scenario.windowSystem.windows.append(makeWindow(id: 9))
    await scenario.command("tiling off")
    #expect(scenario.frame(of: 1) == ManagerHarness.originalFrame(index: 0))
    #expect(scenario.frame(of: 3) == ManagerHarness.originalFrame(index: 2))
    #expect(scenario.workspaces.isEmpty)
  }

  @Test func turningTilingBackOnTilesEverythingOntoTheCurrentWorkspace() async {
    let scenario = await Scenario(workspaces: [1: [1, 2]], showing: [2])
    await scenario.command("tiling off")
    await scenario.command("tiling on")
    #expect(scenario.workspaces == [1: 2, 2: 2])
  }

  @Test func aParkedWindowThatClosesLeavesItsWorkspace() async {
    let scenario = await Scenario(workspaces: [1: [1, 2]], showing: [2])
    await scenario.close(1)
    #expect(scenario.workspaces == [2: 1])
  }

  @Test func aParkedWindowStaysOnItsWorkspaceWhateverItsFrameSays() async {
    let scenario = await Scenario(
      displays: [FakeDisplays.main, FakeDisplays.right], workspaces: [1: [1, 2]], showing: [2])
    // macOS (or the user) moves a parked window onto the other display.
    await scenario.change(
      makeWindow(id: 1, frame: CGRect(x: 2000, y: 100, width: 300, height: 200)))
    #expect(scenario.workspaces == [1: 1, 2: 1])
  }

  @Test func parkedWindowsOverlappingAnotherDisplayComeBackWithTheirWorkspace() async {
    // A tall display to the right: a window parked in the primary's corner overlaps it more
    // than the primary, so by frame alone it would count as being on that display.
    let tall = DisplayInfo(
      id: 3,
      frame: CGRect(x: 1800, y: 0, width: 1920, height: 2400),
      visibleFrame: CGRect(x: 1800, y: 0, width: 1920, height: 2400))
    let scenario = await Scenario(displays: [FakeDisplays.main, tall], workspaces: [1: [1, 2]])
    let slots = [scenario.frame(of: 1), scenario.frame(of: 2)]
    await scenario.command("workspace focus next")
    await scenario.command("workspace focus prev")
    #expect(scenario.workspaces == [1: 1, 2: 1])
    #expect([scenario.frame(of: 1), scenario.frame(of: 2)] == slots)
  }

  @Test func aParkedWindowThatIsMinimizedComesBackOnTheCurrentWorkspace() async {
    let scenario = await Scenario(workspaces: [1: [1, 2]], showing: [2])
    await scenario.change(makeWindow(id: 1, isMinimized: true))
    #expect(scenario.workspaces == [2: 1])
    await scenario.change(makeWindow(id: 1))
    #expect(scenario.workspaces == [1: 2, 2: 1])
  }

  @Test func floatedWindowsBelongToNoWorkspaceAndAreNeverParked() async {
    let scenario = await Scenario(workspaces: [1: [1, 2]])
    await scenario.focus(2)
    await scenario.command("window float toggle")
    let floatedFrame = scenario.frame(of: 2)
    scenario.windowSystem.clearRecordedCalls()
    await scenario.command("workspace focus next")
    #expect(scenario.workspaces == [1: 1])
    #expect(scenario.frame(of: 2) == floatedFrame)
    #expect(scenario.windowSystem.unfocusCount == 0, "a floated window stays on screen, with focus")
  }
}
