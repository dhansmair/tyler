import Testing
import TylerCore
import TylerTestSupport

@testable import TylerServer

/// An app with windows on two displays can end on the one it remembers after tylerd asks for the
/// other, and no focus event follows. tylerd asks once more instead of bringing the remembered
/// window's workspace into view (#87).
@Suite("Workspaces: an app ending on the window it remembers")
@MainActor
struct FocusEndsOnRememberedScenarios {
  /// 1 and 2 in view, 1 focused, 3 parked on the same display, 4 and 5 on the other display. All
  /// are windows of one app unless a test says otherwise.
  private func twoDisplays() async -> Scenario {
    let scenario = await Scenario(
      displays: [FakeDisplays.main, FakeDisplays.secondary],
      workspaces: [1: [1, 2], 2: [3], 5: [4], 6: [5]])
    await scenario.focus(1)
    return scenario
  }

  /// tylerd focuses 2, its echo comes, and the app ends on `remembered`.
  private func askForTwoEndingOn(_ remembered: UInt32, in scenario: Scenario) async {
    await scenario.start("window focus next")
    scenario.harness.windowSystem.send(.focused(WindowID(2)))
    scenario.harness.windowSystem.send(.focused(WindowID(remembered)))
    await scenario.harness.settle()
    await scenario.wait(WorkspaceController.parkedFocusSettling)
  }

  @Test(arguments: [UInt32(3), 5])
  func tylerdAsksAgainInsteadOfSwitching(remembered: UInt32) async {
    let scenario = await twoDisplays()
    await askForTwoEndingOn(remembered, in: scenario)
    scenario.harness.windowSystem.send(.focused(WindowID(2)))
    await scenario.runUntilQuiet()
    #expect(scenario.shown == [1, 5])
    #expect(scenario.windowSystem.focusCalls.suffix(2) == [WindowID(2), WindowID(2)])
  }

  /// macOS reports nothing when the focus doesn't change, so silence means the ask didn't land.
  @Test func aSecondAskThatChangesNothingIsFollowed() async {
    let scenario = await twoDisplays()
    await askForTwoEndingOn(3, in: scenario)
    await scenario.runUntilQuiet()
    #expect(scenario.shown == [2, 5])
  }

  @Test func aSecondAskThatFailsIsFollowed() async {
    let scenario = await twoDisplays()
    await scenario.start("window focus next")
    scenario.harness.windowSystem.send(.focused(WindowID(2)))
    scenario.harness.windowSystem.send(.focused(WindowID(3)))
    await scenario.harness.settle()
    scenario.windowSystem.failingFocus = [WindowID(2)]
    await scenario.runUntilQuiet()
    #expect(scenario.shown == [2, 5])
  }

  @Test func aWantedWindowGoneFromTheWindowServerIsNotAskedForAgain() async {
    let scenario = await twoDisplays()
    scenario.stacking.goneWindows = [WindowID(2)]
    await scenario.start("window focus next")
    scenario.harness.windowSystem.send(.focused(WindowID(3)))
    await scenario.runUntilQuiet()
    #expect(scenario.shown == [2, 5])
    #expect(scenario.windowSystem.focusCalls.filter { $0 == WindowID(2) }.count == 1)
  }

  /// Focusing the window that has the focus asks the app for nothing, so a real move right after
  /// it is followed.
  @Test func aRequestForTheFocusedWindowIsNoRequest() async {
    let scenario = await twoDisplays()
    await scenario.start("display focus 1")
    let focusCalls = scenario.windowSystem.focusCalls.count
    await scenario.focus(3)
    #expect(scenario.shown == [2, 5])
    #expect(scenario.windowSystem.focusCalls.count == focusCalls)
  }

  @Test func aSecondAskThatDoesntHoldIsFollowed() async {
    let scenario = await twoDisplays()
    await askForTwoEndingOn(3, in: scenario)
    scenario.harness.windowSystem.send(.focused(WindowID(2)))
    scenario.harness.windowSystem.send(.focused(WindowID(3)))
    await scenario.runUntilQuiet()
    #expect(scenario.shown == [2, 5])
  }

  @Test func aFocusLongAfterTheRequestSwitches() async {
    let scenario = await twoDisplays()
    await scenario.command("window focus next")
    await scenario.focus(3)
    #expect(scenario.shown == [2, 5])
  }

  @Test func anotherAppsParkedWindowSwitches() async {
    let scenario = await twoDisplays()
    var other = scenario.windowSystem.windows.first { $0.id == WindowID(3) }
    other?.processID = 900
    if let other { await scenario.change(other) }
    await askForTwoEndingOn(3, in: scenario)
    await scenario.runUntilQuiet()
    #expect(scenario.shown == [2, 5])
  }

  @Test func aWindowParkedSinceItWasAskedForIsNotAskedForAgain() async {
    let scenario = await twoDisplays()
    await scenario.start("window focus next")
    await scenario.start("workspace focus 3")
    scenario.harness.windowSystem.send(.focused(WindowID(3)))
    await scenario.runUntilQuiet()
    #expect(scenario.shown == [2, 5])
  }

  /// After a close tylerd focuses the sibling, and the app can go back to its parked window.
  @Test func theFocusTakenBackAfterACloseHolds() async {
    let scenario = await twoDisplays()
    scenario.harness.windowSystem.windows.removeAll { $0.id == WindowID(1) }
    scenario.harness.windowSystem.send(.destroyed(WindowID(1)))
    scenario.harness.windowSystem.send(.focused(WindowID(3)))
    await scenario.harness.settle()
    await scenario.wait(WorkspaceController.parkedFocusSettling)
    scenario.harness.windowSystem.send(.focused(WindowID(2)))
    scenario.harness.windowSystem.send(.focused(WindowID(3)))
    await scenario.harness.settle()
    await scenario.wait(WorkspaceController.parkedFocusSettling)
    scenario.harness.windowSystem.send(.focused(WindowID(2)))
    await scenario.runUntilQuiet()
    #expect(scenario.shown == [1, 5])
    #expect(scenario.windowSystem.focusCalls.last == WindowID(2))
  }
}
