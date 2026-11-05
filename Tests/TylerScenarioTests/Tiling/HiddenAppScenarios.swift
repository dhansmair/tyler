import CoreGraphics
import Testing
import TylerCore
import TylerTestSupport

@testable import TylerServer

/// Hiding an app takes its windows out of the layout and they come back where they were, across
/// workspaces: nothing else tells a hidden window from a shown one (#116).
@Suite("Tiling: a hidden app")
@MainActor
struct HiddenAppScenarios {
  private let area = FakeDisplays.main.visibleFrame

  /// As `MacWindowSystem` reports an app hidden or shown: all its windows in one event.
  private func setHidden(_ isHidden: Bool, _ ids: [UInt32], in scenario: Scenario) async {
    var changed: [WindowInfo] = []
    for id in ids {
      guard let index = scenario.windowSystem.windows.firstIndex(where: { $0.id.rawValue == id })
      else {
        Issue.record("no window \(id)")
        return
      }
      scenario.windowSystem.windows[index].isHidden = isHidden
      changed.append(scenario.windowSystem.windows[index])
    }
    scenario.windowSystem.send(.updatedTogether(changed))
    await scenario.runUntilQuiet()
  }

  @Test func hidingFreesTheSlotAndTheOthersTileAcrossIt() async {
    let scenario = await Scenario(workspaces: [1: [1, 2]])
    await setHidden(true, [2], in: scenario)
    #expect(scenario.list(1) == [1])
    #expect(scenario.frame(of: 1) == area)
    #expect(scenario.windowList.first { $0.id == WindowID(2) }?.isHidden == true)
  }

  @Test func aWindowComesBackToItsPlaceInTheList() async {
    let scenario = await Scenario(workspaces: [1: [1, 2, 3]])
    await setHidden(true, [1], in: scenario)
    #expect(scenario.list(1) == [2, 3])
    await setHidden(false, [1], in: scenario)
    #expect(scenario.list(1) == [1, 2, 3])
  }

  @Test func anAppOnTwoWorkspacesComesBackToBoth() async {
    let scenario = await Scenario(workspaces: [1: [1, 2], 2: [3, 4]])
    await setHidden(true, [2, 4], in: scenario)
    #expect(scenario.list(1) == [1])
    #expect(scenario.list(2) == [3])
    await setHidden(false, [2, 4], in: scenario)
    #expect(scenario.list(1) == [1, 2])
    #expect(scenario.list(2) == [3, 4])
    #expect(scenario.shown == [1])
    #expect(scenario.isParked(4))
  }

  @Test func aWindowBackOnAParkedWorkspaceIsParked() async {
    let scenario = await Scenario(workspaces: [1: [1, 2], 2: [3]])
    await setHidden(true, [2], in: scenario)
    await scenario.command("workspace focus 2")
    await setHidden(false, [2], in: scenario)
    #expect(scenario.list(1) == [1, 2])
    #expect(scenario.shown == [2])
    #expect(scenario.isParked(2))
  }

  /// Parked while hidden, so it doesn't show over the other workspace when it comes back.
  @Test func aHiddenWindowParksWithItsWorkspace() async {
    let scenario = await Scenario(workspaces: [1: [1, 2], 2: [3]])
    await setHidden(true, [2], in: scenario)
    await scenario.command("workspace focus 2")
    #expect(scenario.isParked(2))
  }

  @Test func aHiddenWindowParksWithItsWorkspaceOnASwipe() async {
    let scenario = await Scenario(workspaces: [1: [1, 2], 2: [3]])
    await setHidden(true, [2], in: scenario)
    await scenario.swipe(.left)
    #expect(scenario.shown == [2])
    #expect(scenario.isParked(2))
  }

  @Test func aHiddenWindowParksWithAWorkspacePushedOutOfViewByAnother() async {
    let scenario = await Scenario(
      displays: [FakeDisplays.main, FakeDisplays.secondary], workspaces: [1: [1, 2], 5: [5, 6]])
    await setHidden(true, [6], in: scenario)
    await scenario.command("workspace move-to-display 2")
    #expect(scenario.isParked(5))
    #expect(scenario.isParked(6))
  }

  @Test func theWindowListNamesAHiddenWindowsWorkspace() async {
    let scenario = await Scenario(workspaces: [1: [1, 2], 2: [3]])
    await setHidden(true, [2], in: scenario)
    let listed = scenario.windowList.first { $0.id == WindowID(2) }
    #expect(listed?.workspace == 1)
    #expect(listed?.slot == nil)
  }

  /// An app comes to the front before macOS says it is shown (`macos-behaviour.md`).
  @Test func aWindowThatComesBackWithTheFocusBringsItsWorkspace() async {
    let scenario = await Scenario(workspaces: [1: [1, 2], 2: [3]])
    await setHidden(true, [2], in: scenario)
    await scenario.command("workspace focus 2")
    await scenario.focus(2)
    await setHidden(false, [2], in: scenario)
    #expect(scenario.list(1) == [1, 2])
    #expect(scenario.shown == [1])
  }

  @Test func windowsComingBackTogetherEachFillTheirSlot() async {
    let scenario = await Scenario(workspaces: [1: [1, 2, 3, 4]])
    let windows: [UInt32] = [1, 2, 3, 4]
    let settled = windows.map(scenario.frame(of:))
    await setHidden(true, [2, 3], in: scenario)
    await setHidden(false, [2, 3], in: scenario)
    await scenario.wait(.seconds(1))
    #expect(windows.map(scenario.frame(of:)) == settled)
  }

  @Test func aWindowClosedWhileHiddenIsForgotten() async {
    let scenario = await Scenario(workspaces: [1: [1, 2, 3]])
    await setHidden(true, [2], in: scenario)
    await scenario.close(2)
    #expect(scenario.harness.manager.rows[0][0].members.map(\.rawValue) == [1, 3])
  }

  @Test func aHiddenFloatedWindowStaysFloated() async {
    let scenario = await Scenario(workspaces: [1: [1, 2]])
    await scenario.focus(2)
    await scenario.command("window float on")
    let frame = scenario.frame(of: 2)
    await setHidden(true, [2], in: scenario)
    await setHidden(false, [2], in: scenario)
    #expect(scenario.list(1) == [1])
    #expect(scenario.frame(of: 2) == frame)
    #expect(scenario.windowList.first { $0.id == WindowID(2) }?.isFloated == true)
  }

  /// The focus reaches tylerd before the hide does, and the window server already says the window
  /// is gone (`macos-behaviour.md`).
  @Test func theParkedWindowMacOSFocusesAfterAHideIsNotFollowed() async {
    let scenario = await Scenario(workspaces: [1: [1, 2], 2: [3]])
    await scenario.focus(2)
    let index = scenario.windowSystem.windows.firstIndex { $0.id == WindowID(2) }
    if let index { scenario.windowSystem.windows[index].isHidden = true }
    await scenario.focus(3)
    await setHidden(true, [2], in: scenario)
    #expect(scenario.shown == [1])
    #expect(scenario.focused == 1)
  }

  @Test func aRestartKeepsAHiddenWindowsPlace() async {
    let scenario = await Scenario(workspaces: [1: [1, 2, 3]])
    await setHidden(true, [2], in: scenario)
    let next = await scenario.restart()
    #expect(next.list(1) == [1, 3])
    await setHidden(false, [2], in: next)
    #expect(next.list(1) == [1, 2, 3])
  }

  @Test func aHiddenWindowComesBackToItsWorkspaceOnTheDisplayItMovedTo() async {
    let scenario = await Scenario(
      displays: [FakeDisplays.main, FakeDisplays.secondary], workspaces: [1: [1, 2], 2: [3]])
    await setHidden(true, [2], in: scenario)
    await scenario.command("workspace move-to-display 2")
    await setHidden(false, [2], in: scenario)
    #expect(scenario.workspaces[2] == 1)
    #expect(scenario.list(1) == [1, 2])
  }

  @Test func tilingOffBringsBackAHiddenWindowLeftParked() async {
    let scenario = await Scenario(openAtStart: spread([1, 2, 3]))
    await scenario.focus(3)
    await scenario.command("window move-to-workspace 2")
    #expect(scenario.isParked(3))
    await setHidden(true, [3], in: scenario)
    await scenario.command("workspace focus 2")
    await scenario.command("tiling off")
    #expect(!scenario.isParked(3))
  }

  @Test func tilingOffAndOnKeepsAHiddenWindowsPlace() async {
    let scenario = await Scenario(workspaces: [1: [1, 2, 3]])
    await setHidden(true, [2], in: scenario)
    await scenario.command("tiling off")
    await scenario.command("tiling on")
    await setHidden(false, [2], in: scenario)
    #expect(scenario.list(1) == [1, 2, 3])
  }
}
