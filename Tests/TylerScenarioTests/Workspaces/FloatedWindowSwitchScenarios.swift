import CoreGraphics
import Testing
import TylerCore
import TylerTestSupport

@testable import TylerServer

/// A floated window belongs to its workspace: it parks with it and comes back where it was.
/// Workspace 1 holds window 1, tiled, and window 2, floated; workspace 2 holds window 3.
@Suite("Workspaces: switching with a floated window")
@MainActor
struct FloatedWindowSwitchScenarios {
  private func scenario() async -> Scenario {
    let scenario = await Scenario(workspaces: [1: [1, 2], 2: [3]])
    await scenario.focus(2)
    await scenario.command("window float on")
    return scenario
  }

  @Test func aFloatedWindowParksWithItsWorkspaceAndComesBackWhereItWas() async {
    let scenario = await scenario()
    let floated = scenario.frame(of: 2)
    await scenario.command("workspace focus next")
    #expect(scenario.isParked(2))
    #expect(scenario.workspaces == [1: 1, 2: 1, 3: 2])
    await scenario.command("workspace focus prev")
    #expect(scenario.frame(of: 2) == floated)
    #expect(scenario.list(1) == [1], "it still floats")
  }

  @Test func itComesBackWhereTheUserLastPutIt() async {
    let scenario = await scenario()
    let moved = CGRect(x: 300, y: 200, width: 400, height: 300)
    await scenario.moveByHand(2, to: moved)
    await scenario.command("workspace focus next")
    await scenario.command("workspace focus prev")
    #expect(scenario.frame(of: 2) == moved)
  }

  @Test func aSwipeParksItTooAndBringsItBack() async {
    let scenario = await scenario()
    let floated = scenario.frame(of: 2)
    await scenario.swipe(.left)
    #expect(scenario.shown == [2])
    #expect(scenario.isParked(2))
    await scenario.swipe(.right)
    #expect(scenario.frame(of: 2) == floated)
  }

  /// Focusing a tiled window raises it over a floated one that overlaps it, and macOS raises a
  /// window above another app's only by focusing it.
  @Test func aFloatedWindowThatHadTheFocusGetsItBackWhenItsWorkspaceReturns() async {
    let scenario = await scenario()
    await scenario.command("workspace focus next")
    scenario.windowSystem.clearRecordedCalls()
    await scenario.command("workspace focus prev")
    #expect(scenario.windowSystem.focusCalls.last == WindowID(2))
  }

  @Test func aSwipeBackGivesTheFloatedWindowTheFocusBack() async {
    let scenario = await scenario()
    await scenario.swipe(.left)
    scenario.windowSystem.clearRecordedCalls()
    await scenario.swipe(.right)
    #expect(scenario.windowSystem.focusCalls.last == WindowID(2))
  }

  @Test func aTiledWindowFocusedAfterTheFloatedOneGetsTheFocusBack() async {
    let scenario = await scenario()
    await scenario.focus(1)
    await scenario.command("workspace focus next")
    scenario.windowSystem.clearRecordedCalls()
    await scenario.command("workspace focus prev")
    #expect(scenario.windowSystem.focusCalls.last == WindowID(1))
  }

  @Test func switchingToAnEmptyWorkspaceTakesTheFocusFromIt() async {
    let scenario = await Scenario(workspaces: [1: [1, 2]])
    await scenario.focus(2)
    await scenario.command("window float on")
    scenario.windowSystem.clearRecordedCalls()
    await scenario.command("workspace focus next")
    #expect(scenario.isParked(2))
    #expect(scenario.windowSystem.unfocusCount == 1, "a parked window would get every key")
  }

  @Test func aWorkspaceWithOnlyAFloatedWindowFocusesIt() async {
    let scenario = await Scenario(workspaces: [1: [1], 2: [2]])
    await scenario.command("workspace focus next")
    await scenario.focus(2)
    await scenario.command("window float on")
    await scenario.command("workspace focus prev")
    scenario.windowSystem.clearRecordedCalls()
    await scenario.command("workspace focus next")
    #expect(scenario.windowSystem.focusCalls == [WindowID(2)])
  }

  @Test func focusingAParkedFloatedWindowSwitchesToItsWorkspace() async {
    let scenario = await scenario()
    await scenario.command("workspace focus next")
    await scenario.focus(2)  // the user cmd-tabs to the parked window
    await scenario.wait(WorkspaceController.parkedFocusSettling)
    #expect(scenario.shown == [1])
    #expect(!scenario.isParked(2))
  }
}
