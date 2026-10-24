import CoreGraphics
import Testing
import TylerCore
import TylerTestSupport

@testable import TylerServer

@Suite("Workspaces: move-to-workspace")
@MainActor
struct MoveToWorkspaceScenarios {
  @Test func withoutFollowTheWindowParksAndFocusStays() async {
    let scenario = await Scenario(workspaces: [1: [1, 2]])
    await scenario.focus(2)
    scenario.windowSystem.clearRecordedCalls()
    #expect(
      await scenario.command("window move-to-workspace next") == .message("moved to workspace 2"))
    #expect(scenario.isParked(2))
    #expect(scenario.frame(of: 1) == scenario.rect(.full))
    #expect(scenario.workspaces == [1: 1, 2: 2])
    #expect(scenario.windowSystem.focusCalls == [WindowID(1)])
  }

  @Test(arguments: [false, true])
  func aWindowThatRefusesFocusIsReported(follow: Bool) async {
    let scenario = await Scenario(workspaces: [1: [1, 2]])
    await scenario.focus(2)
    // Without follow, focus goes to the window left behind; with it, to the window moved.
    scenario.windowSystem.failingFocus = [WindowID(follow ? 2 : 1)]
    #expect(
      await scenario.command("window move-to-workspace next\(follow ? " --follow" : "")")
        == .message("moved to workspace 2; cannot focus window \(follow ? 2 : 1): fake refusal"))
  }

  @Test func withFollowTheViewGoesAlong() async {
    let scenario = await Scenario(workspaces: [1: [1, 2]])
    await scenario.focus(2)
    scenario.windowSystem.clearRecordedCalls()
    #expect(
      await scenario.command("window move-to-workspace 3 --follow")
        == .message("moved to workspace 3"))
    #expect(scenario.frame(of: 2) == scenario.rect(.full))
    #expect(scenario.isParked(1))
    #expect(scenario.shown == [3])
    #expect(scenario.windowSystem.focusCalls == [WindowID(2)])
  }

  @Test func theMovedWindowIsFocusedWhenYouGetThere() async {
    let scenario = await Scenario(workspaces: [1: [1, 2, 3]])
    await scenario.focus(3)
    await scenario.command("window move-to-workspace next")
    await scenario.focus(1)
    await scenario.command("window move-to-workspace next")
    scenario.windowSystem.clearRecordedCalls()
    await scenario.command("workspace focus next")
    #expect(scenario.windowSystem.focusCalls == [WindowID(1)])
  }

  @Test func movingTheLastWindowTakesFocusFromItOnceParked() async {
    let scenario = await Scenario(workspaces: [1: [1]])
    await scenario.focus(1)
    scenario.windowSystem.clearRecordedCalls()
    await scenario.command("window move-to-workspace prev")
    #expect(scenario.workspaces == [1: 4])
    #expect(scenario.isParked(1))
    #expect(scenario.windowSystem.focusCalls.isEmpty)
    #expect(scenario.windowSystem.unfocusCount == 1)
  }

  @Test func movingToTheSameWorkspaceDoesNothing() async {
    let scenario = await Scenario(workspaces: [1: [1, 2]])
    await scenario.focus(1)
    scenario.windowSystem.clearRecordedCalls()
    #expect(
      await scenario.command("window move-to-workspace 1") == .message("already on workspace 1"))
    #expect(scenario.windowSystem.moves.isEmpty)
  }

  @Test func onlyATiledFocusedWindowCanMove() async {
    let scenario = await Scenario(openAtStart: spread([1]) + [makeWindow(id: 7, kind: .dialog)])
    #expect(
      await scenario.command("window move-to-workspace next")
        == .error("the focused window is not tiled"))
    await scenario.focus(7)
    #expect(
      await scenario.command("window move-to-workspace next")
        == .error("the focused window is not tiled"))
  }

  @Test func aTargetOutOfRangeIsAnError() async {
    let scenario = await Scenario(workspaces: [1: [1]])
    await scenario.focus(1)
    #expect(
      await scenario.command("window move-to-workspace 9 --follow")
        == .error("workspace 9 does not exist (use 1 to 4)"))
  }

  // MARK: Focus-driven switching

  @Test func focusingAParkedWindowSwitchesToItsWorkspace() async {
    let scenario = await Scenario(workspaces: [1: [1], 3: [2]])
    scenario.windowSystem.clearRecordedCalls()
    await scenario.focus(2)  // the user cmd-tabs to the parked window
    #expect(scenario.shown == [3])
    #expect(scenario.frame(of: 2) == scenario.rect(.full))
    #expect(scenario.isParked(1))
    #expect(scenario.windowSystem.focusCalls.isEmpty, "the OS already focused it")
  }

  @Test func theEchoOfTylerdsOwnFocusDoesNotSwitchBack() async {
    let scenario = await Scenario(workspaces: [1: [1], 2: [2]])
    await scenario.command("workspace focus next")  // tylerd focuses window 2
    await scenario.command("workspace focus prev")  // and quickly back
    // Window 2's focus event arrives late, while it is parked again.
    await scenario.focus(2)
    #expect(scenario.shown == [1])
  }

  @Test func focusingAParkedWindowWithTilingOffDoesNotSwitch() async {
    let scenario = await Scenario(workspaces: [1: [1], 2: [2]])
    await scenario.command("tiling off")
    await scenario.focus(2)
    #expect(scenario.shown == [1])
  }
}
