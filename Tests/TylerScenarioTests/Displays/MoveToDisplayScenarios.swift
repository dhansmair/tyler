import CoreGraphics
import Testing
import TylerCore
import TylerTestSupport

/// Sending windows to another display. The laptop (`main`, display 1, workspaces 1 to 4) holds
/// windows 1 and 2; the external display above it (`secondary`, display 2, workspaces 5 to 8) holds
/// windows 3 and 4 on workspace 5.
@Suite("Several displays: tyler window move-to-display")
@MainActor
struct MoveToDisplayScenarios {
  private func scenario(laptop: [UInt32] = [1, 2]) async -> Scenario {
    await Scenario(
      displays: [FakeDisplays.main, FakeDisplays.secondary], workspaces: [1: laptop, 5: [3, 4]])
  }

  @Test func withoutFollowTheWindowTakesItsSlotThereAndFocusStays() async {
    let scenario = await scenario()
    await scenario.focus(2)
    #expect(
      await scenario.command("window move-to-display 2") == .message("moved to display 2"))
    #expect(scenario.workspaces[2] == 5)
    #expect(scenario.rect(.full, display: 2).contains(scenario.frame(of: 2) ?? .zero))
    #expect(scenario.frame(of: 1) == scenario.rect(.full), "window 1 fills the laptop alone")
    #expect(scenario.windowSystem.focusCalls.last == WindowID(1))
    #expect(scenario.focusedDisplay == 1)
  }

  @Test func theWindowGoesInAfterTheFocusedOneThere() async {
    let scenario = await scenario()
    await scenario.focus(3)
    await scenario.focus(2)
    await scenario.command("window move-to-display next")
    #expect(scenario.list(5) == [3, 2, 4])
    await scenario.command("display focus 2")
    #expect(scenario.windowSystem.focusCalls.last == WindowID(2), "it is the one focused there")
  }

  @Test func withFollowTheFocusGoesAlong() async {
    let scenario = await scenario()
    await scenario.focus(2)
    #expect(
      await scenario.command("window move-to-display 2 --follow")
        == .message("moved to display 2"))
    #expect(scenario.focusedDisplay == 2)
    #expect(scenario.windowSystem.focusCalls.last == WindowID(2))
    #expect(scenario.rect(.full, display: 2).contains(scenario.frame(of: 2) ?? .zero))
  }

  @Test func prevAndNextWrapFromTheWindowsDisplay() async {
    let scenario = await scenario()
    await scenario.focus(4)
    #expect(
      await scenario.command("window move-to-display next") == .message("moved to display 1"))
    #expect(scenario.workspaces[4] == 1)
    #expect(scenario.rect(.full).contains(scenario.frame(of: 4) ?? .zero))
  }

  @Test func aWindowSentToAParkedWorkspaceThereStaysOnScreenOnTheTarget() async {
    let scenario = await Scenario(
      displays: [FakeDisplays.main, FakeDisplays.secondary], workspaces: [1: [1, 2], 5: [3, 4]],
      showing: [1, 6])
    await scenario.focus(1)
    await scenario.command("window move-to-display 2")
    #expect(scenario.workspaces[1] == 6, "the workspace on screen there")
    #expect(scenario.frame(of: 1) == scenario.rect(.full, display: 2))
  }

  @Test func sendingTheLastWindowAwayLeavesNoFocusOnTheLaptop() async {
    let scenario = await scenario(laptop: [1])
    await scenario.focus(1)
    scenario.windowSystem.clearRecordedCalls()
    await scenario.command("window move-to-display 2")
    #expect(scenario.windowSystem.focusCalls.isEmpty)
    #expect(scenario.windowSystem.unfocusCount == 1)
    #expect(scenario.focusedDisplay == 1)
  }

  @Test func theWindowsOwnDisplayChangesNothing() async {
    let scenario = await scenario()
    await scenario.focus(1)
    scenario.windowSystem.clearRecordedCalls()
    #expect(
      await scenario.command("window move-to-display 1 --follow")
        == .message("already on display 1"))
    #expect(scenario.windowSystem.moves.isEmpty)
  }

  @Test func onlyATiledFocusedWindowCanMove() async {
    let scenario = await Scenario(
      openAtStart: spread([1]) + [makeWindow(id: 7, kind: .dialog)],
      displays: [FakeDisplays.main, FakeDisplays.secondary])
    await scenario.focus(7)
    #expect(
      await scenario.command("window move-to-display next")
        == .error("the focused window is not tiled"))
  }

  @Test func aNumberNoDisplayHasIsAnError() async {
    let scenario = await scenario()
    await scenario.focus(1)
    #expect(
      await scenario.command("window move-to-display 3")
        == .error("display 3 does not exist (use 1 to 2)"))
    #expect(scenario.workspaces[1] == 1)
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
