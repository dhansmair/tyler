import CoreGraphics
import Testing
import TylerCore
import TylerTestSupport

/// A swipe acts on the display under the pointer, whichever display has focus: the laptop
/// (`main`: window 1 on workspace 1, window 2 on workspace 2) and the external display above it
/// (`secondary`: window 3 on workspace 5, window 4 on workspace 6).
@Suite("Several displays: swipes under the pointer")
@MainActor
struct SwipeUnderPointerScenarios {
  private let overTheExternalDisplay = CGPoint(x: 1000, y: -700)
  private let displays = [FakeDisplays.main, FakeDisplays.secondary]

  private func scenario() async -> Scenario {
    let scenario = await Scenario(
      displays: displays, workspaces: [1: [1], 2: [2], 5: [3], 6: [4]])
    await scenario.focus(1)
    scenario.windowSystem.clearRecordedCalls()
    return scenario
  }

  @Test func aSwipeOverTheExternalDisplaySwitchesTheExternalDisplaysWorkspaceAndFocusesIt() async {
    let scenario = await scenario()
    scenario.pointer.location = overTheExternalDisplay
    await scenario.swipe(.left)

    #expect(scenario.focusedDisplay == 2)
    #expect(scenario.shown == [1, 6], "the laptop stays on workspace 1")
    #expect(scenario.frame(of: 4) == scenario.rect(.full, display: 2))
    #expect(scenario.isParked(3))
    #expect(scenario.frame(of: 1) == scenario.rect(.full))
  }

  @Test func aSwipeOverTheLaptopActsThereWhileTheExternalDisplayHasFocus() async {
    let scenario = await scenario()
    await scenario.focus(3)
    #expect(scenario.focusedDisplay == 2)

    await scenario.swipe(.left)
    #expect(scenario.focusedDisplay == 1)
    #expect(scenario.shown == [2, 5], "the external display stays on workspace 5")
    #expect(scenario.frame(of: 2) == scenario.rect(.full))
    #expect(scenario.frame(of: 3) == scenario.rect(.full, display: 2))
  }

  @Test func aSwipeOverTheExternalDisplayScrollsItsStrip() async {
    let scenario = await Scenario(
      displays: displays, workspaces: [1: [1], 2: [2], 5: [3, 4, 5]])
    await scenario.focus(3)
    await scenario.command("layout set strip")
    await scenario.focus(1)
    #expect(scenario.frame(of: 3) == scenario.rect(.leftHalf, display: 2))

    scenario.pointer.location = overTheExternalDisplay
    await scenario.swipe(.left)
    #expect(scenario.frame(of: 4) == scenario.rect(.leftHalf, display: 2), "window 4 comes first")
    #expect(scenario.isParked(3))
    #expect(scenario.frame(of: 1) == scenario.rect(.full), "the laptop doesn't move")
  }
}
