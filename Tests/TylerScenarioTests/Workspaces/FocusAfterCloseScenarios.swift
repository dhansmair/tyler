import CoreGraphics
import Testing
import TylerCore
import TylerTestSupport

@testable import TylerServer

/// When the window holding the focus goes away, macOS picks the next one, even on a parked
/// workspace. The user didn't ask for that window, so its workspace stays parked (#12).
@Suite("Workspaces: the focus macOS picks after a close")
@MainActor
struct FocusAfterCloseScenarios {
  /// 1 and 2 in view with 1 focused, 3 parked on the same display, 4 and 5 on the other display.
  private func twoDisplays() async -> Scenario {
    let scenario = await Scenario(
      displays: [FakeDisplays.main, FakeDisplays.secondary],
      workspaces: [1: [1, 2], 2: [3], 5: [4], 6: [5]])
    await scenario.focus(1)
    return scenario
  }

  @Test func aCloseThenAFocusOnAParkedWindowStaysAndFocusesTheSibling() async {
    let scenario = await twoDisplays()
    await scenario.closeThenFocus(1, next: 3)
    #expect(scenario.shown == [1, 5])
    #expect(scenario.windowSystem.focusCalls.last == WindowID(2))
  }

  @Test func aFocusThatComesBeforeTheCloseAlsoStays() async {
    let scenario = await twoDisplays()
    await scenario.focusThenClose(1, next: 3)
    #expect(scenario.shown == [1, 5])
    #expect(scenario.windowSystem.focusCalls.last == WindowID(2))
  }

  @Test func aWindowGoneFromTheWindowServerAloneStays() async {
    let scenario = await twoDisplays()
    scenario.stacking.goneWindows = [WindowID(1)]
    await scenario.focus(3)
    #expect(scenario.shown == [1, 5])
    #expect(scenario.windowSystem.focusCalls.last == WindowID(1))
  }

  @Test func theWorkspaceLeftEmptyStaysAndTakesTheFocusAway() async {
    let scenario = await twoDisplays()
    await scenario.close(2)
    await scenario.closeThenFocus(1, next: 3)
    #expect(scenario.shown == [1, 5])
    #expect(scenario.windowSystem.unfocusCount == 1)
  }

  @Test func aParkedWindowOnTheOtherDisplayStaysParked() async {
    let scenario = await twoDisplays()
    await scenario.closeThenFocus(1, next: 5)
    #expect(scenario.shown == [1, 5])
    #expect(scenario.focusedDisplay == 1)
    #expect(scenario.windowSystem.focusCalls.last == WindowID(2))
  }

  @Test func aChainOfFocusesKeepsTheWindowThatWentAway() async {
    let scenario = await twoDisplays()
    await scenario.closeThenFocus(1, next: 3, 5)
    #expect(scenario.shown == [1, 5])
  }

  @Test func aNewerFocusInViewEndsTheWait() async {
    let scenario = await twoDisplays()
    let focusCalls = scenario.windowSystem.focusCalls.count
    await scenario.closeThenFocus(1, next: 3, 2)
    #expect(scenario.shown == [1, 5])
    #expect(scenario.windowSystem.focusCalls.count == focusCalls)
  }

  @Test func whileDisplaysSettleTheClosedWindowIsSkipped() async {
    let scenario = await twoDisplays()
    await scenario.beginDisplayChange(to: [FakeDisplays.main, FakeDisplays.secondary])
    await scenario.closeThenFocus(1, next: 3)
    #expect(scenario.windowSystem.focusCalls.last == WindowID(2))
  }

  /// A later focus on that window, by the user this time.
  @Test func aRepeatFocusAfterTakingItBackSwitches() async {
    let scenario = await twoDisplays()
    await scenario.closeThenFocus(1, next: 3)
    await scenario.focus(3)
    #expect(scenario.shown == [2, 5])
  }

  // Each of these still follows the focus.

  @Test func aBackgroundWindowClosingTakesNothingAway() async {
    let scenario = await twoDisplays()
    await scenario.closeThenFocus(2, next: 3)
    #expect(scenario.shown == [2, 5])
  }

  @Test func aFocusWithTheOldWindowStillThereSwitches() async {
    let scenario = await twoDisplays()
    await scenario.focus(3)
    #expect(scenario.shown == [2, 5])
  }

  @Test func aDialogClosingAndFocusingAParkedWindowSwitches() async {
    let scenario = await twoDisplays()
    let dialog = makeWindow(
      id: 9, frame: CGRect(x: 100, y: 100, width: 200, height: 100), kind: .dialog)
    await scenario.open(dialog)
    await scenario.focus(9)
    await scenario.closeThenFocus(9, next: 3)
    #expect(scenario.shown == [2, 5])
  }

  /// The app's last window closed and macOS focused nothing: a focus long after is the user's.
  @Test func aFocusLongAfterTheCloseSwitches() async {
    let scenario = await twoDisplays()
    await scenario.close(2)
    await scenario.close(1)
    await scenario.focus(3)
    #expect(scenario.shown == [2, 5])
  }

  @Test func aNewWindowFocusedBeforeItsCreationIsStillStandardWhenItCloses() async {
    let scenario = await twoDisplays()
    let window = makeWindow(id: 9, frame: CGRect(x: 100, y: 100, width: 300, height: 200))
    scenario.harness.windowSystem.send(.focused(WindowID(9)))
    await scenario.open(window)
    await scenario.closeThenFocus(9, next: 3)
    #expect(scenario.shown == [1, 5])
  }
}
