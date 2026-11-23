import CoreGraphics
import Testing
import TylerCore
import TylerTestSupport

@testable import TylerServer

/// When the focused window closes, the window that takes its place in the list gets the focus,
/// whatever the app picks (#126).
@Suite("Workspaces: the focus after a close goes to the window that takes its place")
@MainActor
struct FocusSuccessorScenarios {
  /// 1, 2 and 3 in view, focused in turn as given, 4 parked.
  private func threeWindows(focusing order: UInt32...) async -> Scenario {
    let scenario = await Scenario(workspaces: [1: [1, 2, 3], 2: [4]])
    for window in order { await scenario.focus(window) }
    return scenario
  }

  @Test func withNoFocusFollowingTheNextWindowGetsIt() async {
    let scenario = await threeWindows(focusing: 1)
    await scenario.close(1)
    #expect(scenario.windowSystem.focusCalls.last == WindowID(2))
  }

  @Test func theLastWindowClosingHandsTheFocusToTheNewLast() async {
    let scenario = await threeWindows(focusing: 3)
    await scenario.close(3)
    #expect(scenario.windowSystem.focusCalls.last == WindowID(2))
  }

  @Test func tylerWindowCloseFocusesTheNextWindow() async {
    let scenario = await threeWindows(focusing: 2)
    await scenario.command("window close")
    #expect(scenario.windowSystem.focusCalls.last == WindowID(3))
  }

  /// macOS 27 reports the app's pick, its most recent window, before the close.
  @Test func theAppsPickBeforeTheCloseIsTakenBack() async {
    let scenario = await threeWindows(focusing: 3, 1)
    await scenario.focusThenClose(1, next: 3)
    #expect(scenario.windowSystem.focusCalls.last == WindowID(2))
    #expect(scenario.shown == [1])
  }

  /// macOS 26.7 reports the app's pick about 50 ms after the close, after tylerd's own focus.
  @Test func theAppsPickAfterTylerdsFocusIsTakenBack() async {
    let scenario = await threeWindows(focusing: 3, 1)
    await scenario.closeThenFocus(1, next: 2, 3)
    #expect(scenario.windowSystem.focusCalls.suffix(2) == [WindowID(2), WindowID(2)])
  }

  /// The app reporting the window tylerd handed the focus to once more needs nothing.
  @Test func aRepeatedFocusOfTheNextWindowNeedsNoFocusCall() async {
    let scenario = await threeWindows(focusing: 1)
    let focusCalls = scenario.windowSystem.focusCalls
    await scenario.closeThenFocus(1, next: 2, 2)
    #expect(scenario.windowSystem.focusCalls == focusCalls + [WindowID(2)])
  }

  @Test func aWindowOnNoWorkspaceFocusedAfterTheCloseKeepsIt() async {
    let scenario = await threeWindows(focusing: 1)
    let dialog = makeWindow(
      id: 9, frame: CGRect(x: 100, y: 100, width: 200, height: 100), kind: .dialog)
    await scenario.open(dialog)
    await scenario.focus(1)
    let focusCalls = scenario.windowSystem.focusCalls
    await scenario.closeThenFocus(1, next: 2, 9)
    #expect(scenario.windowSystem.focusCalls == focusCalls + [WindowID(2)])
  }

  /// The user's own focus, once the close is forgotten.
  @Test func aFocusInViewLongAfterTheCloseIsFollowed() async {
    let scenario = await threeWindows(focusing: 1)
    await scenario.close(1)
    let focusCalls = scenario.windowSystem.focusCalls
    await scenario.focus(3)
    #expect(scenario.windowSystem.focusCalls == focusCalls)
  }

  @Test func aPickOfTheNextWindowNeedsNoFocusCall() async {
    let scenario = await threeWindows(focusing: 1)
    let focusCalls = scenario.windowSystem.focusCalls.count
    await scenario.focusThenClose(1, next: 2)
    #expect(scenario.windowSystem.focusCalls.count == focusCalls)
  }

  /// The user moved on, and the window they left closed later, by its app.
  @Test func theWindowAFocusLeftLongAgoClosingLeavesTheFocus() async {
    let scenario = await threeWindows(focusing: 1, 3)
    let focusCalls = scenario.windowSystem.focusCalls.count
    await scenario.close(1)
    #expect(scenario.windowSystem.focusCalls.count == focusCalls)
  }

  @Test func aQuitClosingTwoWindowsInARowEndsOnTheRest() async {
    let scenario = await threeWindows(focusing: 1)
    await scenario.closeInTurn(1, 2)
    #expect(scenario.windowSystem.focusCalls.last == WindowID(3))
    #expect(scenario.list(1) == [3])
  }

  /// A focus on a parked window, still waiting to last, and then that window closes: its own
  /// workspace remembers the window that took its place, and the one in view keeps the focus.
  @Test func aParkedWindowClosingWithTheFocusHandsItOnInItsOwnWorkspace() async {
    let scenario = await Scenario(workspaces: [1: [1, 2], 2: [3, 4, 5]])
    await scenario.focus(1)
    scenario.harness.windowSystem.send(.focused(WindowID(4)))
    await scenario.harness.settle()
    await scenario.close(4)
    #expect(scenario.shown == [1])
    await scenario.command("workspace focus 2")
    #expect(scenario.windowSystem.focusCalls.last == WindowID(5))
  }

  @Test func aFloatedWindowClosingFocusesTheTiledOne() async {
    let scenario = await threeWindows(focusing: 2)
    await scenario.command("window float on")
    await scenario.close(2)
    #expect(scenario.windowSystem.focusCalls.last == WindowID(3))
  }

  @Test func aCloseOnTheDisplayACommandLeftFocusesItsNextWindow() async {
    let scenario = await Scenario(
      displays: [FakeDisplays.main, FakeDisplays.secondary], workspaces: [1: [1, 2], 5: [5]])
    await scenario.focus(1)
    await scenario.command("display focus 2")
    await scenario.close(1)
    #expect(scenario.focusedDisplay == 1)
    #expect(scenario.windowSystem.focusCalls.last == WindowID(2))
  }

  @Test func aDialogClosingLeavesTheFocusToItsApp() async {
    let scenario = await threeWindows(focusing: 1)
    let dialog = makeWindow(
      id: 9, frame: CGRect(x: 100, y: 100, width: 200, height: 100), kind: .dialog)
    await scenario.open(dialog)
    await scenario.focus(9)
    let focusCalls = scenario.windowSystem.focusCalls.count
    await scenario.close(9)
    #expect(scenario.windowSystem.focusCalls.count == focusCalls)
  }

  @Test func withTilingOffMacOSDecides() async {
    let scenario = await threeWindows(focusing: 1)
    await scenario.command("tiling off")
    let focusCalls = scenario.windowSystem.focusCalls.count
    await scenario.close(1)
    #expect(scenario.windowSystem.focusCalls.count == focusCalls)
  }
}
