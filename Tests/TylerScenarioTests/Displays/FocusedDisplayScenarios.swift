import CoreGraphics
import Testing
import TylerConfig
import TylerCore
import TylerTestSupport

/// Commands act on the focused display. The laptop (`main`, workspaces 1 to 4) holds windows 1
/// and 2; the external display above it (`secondary`, 5 to 8) holds windows 3 and 4 on workspace 5.
@Suite("Several displays: the focused display")
@MainActor
struct FocusedDisplayScenarios {
  private func scenario(config: Config = Config()) async -> Scenario {
    await Scenario(
      displays: [FakeDisplays.main, FakeDisplays.secondary], workspaces: [1: [1, 2], 5: [3, 4]],
      config: config)
  }

  @Test func aWorkspaceOnTheExternalDisplaySwitchesThereAndFocusesTheExternalDisplay() async {
    let scenario = await scenario()
    await scenario.focus(1)
    let laptop = scenario.frame(of: 1)
    #expect(await scenario.command("workspace focus 6") == .message("workspace 6"))
    #expect(scenario.focusedDisplay == 2)
    #expect(scenario.isParked(3))
    #expect(scenario.isParked(4))
    #expect(scenario.frame(of: 1) == laptop, "the laptop stays as it was")
  }

  @Test func prevAndNextStayOnTheFocusedDisplay() async {
    let scenario = await scenario()
    await scenario.command("workspace focus 6")
    #expect(await scenario.command("workspace focus next") == .message("workspace 7"))
    #expect(await scenario.command("workspace focus prev") == .message("workspace 6"))
    #expect(scenario.shown == [1, 6], "the laptop still shows 1")
  }

  @Test func anEmptyWorkspaceKeepsItsDisplayFocused() async {
    let scenario = await scenario()
    await scenario.command("workspace focus 7")
    #expect(scenario.focusedDisplay == 2)
    #expect(await scenario.command("workspace focus prev") == .message("workspace 6"))
  }

  @Test func aWorkspaceOnScreenOnTheExternalDisplayJustTakesTheFocusThere() async {
    let scenario = await scenario()
    await scenario.focus(1)
    scenario.windowSystem.clearRecordedCalls()
    #expect(await scenario.command("workspace focus 5") == .message("workspace 5"))
    #expect(scenario.focusedDisplay == 2)
    #expect(scenario.windowSystem.focusCalls.last == WindowID(3))
    #expect(scenario.windowSystem.moves.isEmpty)
  }

  @Test func layoutCommandsActOnTheFocusedDisplay() async {
    let scenario = await scenario()
    await scenario.focus(3)
    #expect(await scenario.command("layout set full") == .message("layout full"))
    #expect(scenario.frame(of: 3) == scenario.rect(.full, display: 2))
    #expect(scenario.frame(of: 4) == scenario.rect(.full, display: 2))
    #expect(scenario.layout(1) == .tall, "the laptop keeps its layout")
  }

  @Test func focusingAWindowFocusesItsDisplay() async {
    let scenario = await scenario()
    await scenario.focus(4)
    #expect(scenario.focusedDisplay == 2)
    await scenario.focus(2)
    #expect(scenario.focusedDisplay == 1)
  }

  @Test func focusingAParkedWindowOnTheExternalDisplayShowsItsWorkspaceThere() async {
    let scenario = await Scenario(
      displays: [FakeDisplays.main, FakeDisplays.secondary],
      workspaces: [1: [1, 2], 5: [3], 6: [4]])
    await scenario.focus(1)
    #expect(scenario.focusedDisplay == 1)

    await scenario.focus(4)
    #expect(scenario.focusedDisplay == 2)
    #expect(scenario.shown == [1, 6])
    #expect(scenario.frame(of: 4) == scenario.rect(.full, display: 2))
    #expect(scenario.isParked(3))
  }

  @Test func aWindowSentToAHiddenWorkspaceOnTheExternalDisplayParksThere() async {
    let scenario = await scenario()
    await scenario.focus(2)
    #expect(
      await scenario.command("window move-to-workspace 6") == .message("moved to workspace 6"))
    #expect(scenario.workspaces[2] == 6)
    let external = scenario.rect(.full, display: 2)
    #expect(scenario.frame(of: 2)?.minX == external.maxX - 1, "parked at its right edge")
    #expect(external.contains(scenario.frame(of: 2)?.origin ?? .zero))
    #expect(scenario.frame(of: 1) == scenario.rect(.full), "window 1 fills the laptop alone")
    #expect(scenario.windowSystem.focusCalls.last == WindowID(1), "focus stays on the laptop")
    #expect(scenario.focusedDisplay == 1)
  }

  @Test func aWindowSentToTheWorkspaceOnScreenOnTheExternalDisplayTakesItsSlotThere() async {
    let scenario = await scenario()
    await scenario.focus(2)
    await scenario.command("window move-to-workspace 5")
    #expect(scenario.workspaces[2] == 5)
    #expect(scenario.rect(.full, display: 2).contains(scenario.frame(of: 2) ?? .zero))
  }

  @Test func followingAWindowToTheExternalDisplayShowsItsWorkspaceThere() async {
    let scenario = await scenario()
    await scenario.focus(2)
    await scenario.command("window move-to-workspace 6 --follow")
    #expect(scenario.focusedDisplay == 2)
    #expect(scenario.frame(of: 2) == scenario.rect(.full, display: 2))
    #expect(scenario.isParked(3))
    #expect(scenario.windowSystem.focusCalls.last == WindowID(2))
  }

  @Test func aFocusedWindowArrivingOnAHiddenWorkspaceOfTheExternalDisplayShowsItThere() async {
    let scenario = await scenario(config: Config(apps: ["firefox": Config.App(workspace: 6)]))
    var firefox = makeWindow(
      id: 9, frame: CGRect(x: 700, y: 100, width: 300, height: 200), isFocused: true)
    firefox.appName = "Firefox"
    await scenario.open(firefox)
    await scenario.focus(9)
    #expect(scenario.focusedDisplay == 2)
    #expect(scenario.frame(of: 9) == scenario.rect(.full, display: 2))
  }

  @Test func theErrorNamesTheWorkspacesOfEveryDisplay() async {
    #expect(
      await scenario().command("workspace focus 9")
        == .error("workspace 9 does not exist (use 1 to 8)"))
  }
}
