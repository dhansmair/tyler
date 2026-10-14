import CoreGraphics
import Testing
import TylerCore
import TylerTestSupport

@testable import TylerServer

/// Sending windows to another display. The laptop (`main`, display 1, workspaces 1 to 4) holds
/// windows 1 and 2; the external display above it (`secondary`, display 2, workspaces 5 to 8) holds
/// windows 3 and 4 on workspace 5.
@Suite("Several displays: tyler window move-to-display")
@MainActor
struct MoveToDisplayScenarios {
  private let external = FakeDisplays.secondary

  private func onExternal(_ id: UInt32) -> WindowInfo {
    makeWindow(id: id, frame: CGRect(x: 100 + CGFloat(id) * 50, y: -1000, width: 300, height: 200))
  }

  private func harness(laptop: [UInt32] = [1, 2]) -> ManagerHarness {
    ManagerHarness(
      laptop, extra: [onExternal(3), onExternal(4)],
      displays: FakeDisplays(displays: [FakeDisplays.main, FakeDisplays.secondary]))
  }

  private func focusedKey(_ harness: ManagerHarness) -> DisplayKey {
    harness.manager.rows.focusedKey
  }

  @Test func withoutFollowTheWindowTakesItsSlotThereAndFocusStays() async {
    let harness = harness()
    await harness.osFocus(2)
    #expect(
      harness.manager.moveToDisplay(.number(2), follow: false) == .message("moved to display 2"))
    #expect(harness.workspaces()[2] == 5)
    #expect(external.visibleFrame.contains(harness.frame(of: 2) ?? .zero))
    #expect(harness.frame(of: 1) == harness.area, "window 1 fills the laptop alone")
    #expect(harness.windowSystem.focusCalls.last == WindowID(1))
    #expect(focusedKey(harness) == FakeDisplays.main.key)
  }

  @Test func theWindowGoesInAfterTheFocusedOneThere() async {
    let harness = harness()
    await harness.osFocus(3)
    await harness.osFocus(2)
    _ = harness.manager.moveToDisplay(.next, follow: false)
    #expect(harness.manager.rows[1].current.windows == [WindowID(3), WindowID(2), WindowID(4)])
    #expect(harness.manager.rows[1].current.focused == WindowID(2))
  }

  @Test func withFollowTheFocusGoesAlong() async {
    let harness = harness()
    await harness.osFocus(2)
    #expect(
      harness.manager.moveToDisplay(.number(2), follow: true) == .message("moved to display 2"))
    #expect(focusedKey(harness) == external.key)
    #expect(harness.windowSystem.focusCalls.last == WindowID(2))
    #expect(external.visibleFrame.contains(harness.frame(of: 2) ?? .zero))
  }

  @Test func prevAndNextWrapFromTheWindowsDisplay() async {
    let harness = harness()
    await harness.osFocus(4)
    #expect(harness.manager.moveToDisplay(.next, follow: false) == .message("moved to display 1"))
    #expect(harness.workspaces()[4] == 1)
    #expect(harness.area.contains(harness.frame(of: 4) ?? .zero))
  }

  @Test func aWindowSentToAParkedWorkspaceThereStaysOnScreenOnTheTarget() async {
    let harness = harness()
    await harness.osFocus(3)
    _ = harness.manager.switchWorkspace(.number(6))
    await harness.osFocus(1)
    _ = harness.manager.moveToDisplay(.number(2), follow: false)
    #expect(harness.workspaces()[1] == 6, "the workspace on screen there")
    #expect(harness.frame(of: 1) == external.visibleFrame)
  }

  @Test func sendingTheLastWindowAwayLeavesNoFocusOnTheLaptop() async {
    let harness = harness(laptop: [1])
    await harness.osFocus(1)
    harness.windowSystem.clearRecordedCalls()
    _ = harness.manager.moveToDisplay(.number(2), follow: false)
    #expect(harness.windowSystem.focusCalls.isEmpty)
    #expect(harness.windowSystem.unfocusCount == 1)
    #expect(focusedKey(harness) == FakeDisplays.main.key)
  }

  @Test func theWindowsOwnDisplayChangesNothing() async {
    let harness = harness()
    await harness.osFocus(1)
    harness.windowSystem.clearRecordedCalls()
    #expect(
      harness.manager.moveToDisplay(.number(1), follow: true) == .message("already on display 1"))
    #expect(harness.windowSystem.moves.isEmpty)
  }

  @Test func onlyATiledFocusedWindowCanMove() async {
    let harness = ManagerHarness(
      [1], extra: [makeWindow(id: 7, kind: .dialog)],
      displays: FakeDisplays(displays: [FakeDisplays.main, FakeDisplays.secondary]))
    await harness.osFocus(7)
    #expect(
      harness.manager.moveToDisplay(.next, follow: false)
        == .error("the focused window is not tiled"))
  }

  @Test func aNumberNoDisplayHasIsAnError() async {
    let harness = harness()
    await harness.osFocus(1)
    #expect(
      harness.manager.moveToDisplay(.number(3), follow: false)
        == .error("display 3 does not exist (use 1 to 2)"))
    #expect(harness.workspaces()[1] == 1)
  }

  @Test func theRequestReachesTheCommand() async {
    let harness = harness()
    await harness.osFocus(1)
    #expect(
      harness.manager.handle(.moveToDisplay(.number(2), follow: true))
        == .message("moved to display 2"))
  }

  private static let twoDisplays = [FakeDisplays.main, FakeDisplays.right]

  @Test func theWindowGoesInAfterTheFocusedOneAndBothDisplaysRetile() async {
    let scenario = await Scenario(
      displays: Self.twoDisplays, workspaces: [1: [1, 2], 5: [3, 4]])
    await scenario.focus(2)
    await scenario.command("window move-to-display next")
    #expect(scenario.list(1) == [1])
    #expect(scenario.list(5) == [3, 2, 4])
    #expect(scenario.frame(of: 1) == scenario.rect(.full))
    #expect(scenario.frame(of: 3) == scenario.rect(.leftHalf, display: 2))
    #expect(scenario.frame(of: 2) == scenario.rect(.rightTop, display: 2))
    #expect(scenario.frame(of: 4) == scenario.rect(.rightBottom, display: 2))
  }

  @Test func withoutFollowTheFocusStaysOnTheDisplayItLeft() async {
    let scenario = await Scenario(displays: Self.twoDisplays, workspaces: [1: [1, 2], 5: [3]])
    await scenario.focus(2)
    await scenario.command("window move-to-display next")
    #expect(scenario.focused == 1)
  }

  @Test func withFollowTheFocusGoesAlongToTheOtherDisplay() async {
    let scenario = await Scenario(displays: Self.twoDisplays, workspaces: [1: [1, 2], 5: [3]])
    await scenario.focus(2)
    await scenario.command("window move-to-display next --follow")
    #expect(scenario.focused == 2)
  }
}
