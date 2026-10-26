import CoreGraphics
import Testing
import TylerCore
import TylerTestSupport

@testable import TylerServer

/// The strip layout on the primary display: three half windows, two in view at a time.
@Suite("Strip layout")
@MainActor
struct StripScenarios {
  /// Where the two windows in view go: the same halves as `tall` with two windows.
  private let halves = TallLayout().frames(count: 2, in: FakeDisplays.main.visibleFrame)

  /// Windows 1, 2 and 3 in the strip, window 1 focused.
  private func strip(displays: [DisplayInfo] = [FakeDisplays.main]) async -> Scenario {
    let scenario = await Scenario(openAtStart: spread([1, 2, 3]), displays: displays)
    await scenario.focus(1)
    await scenario.command("layout set strip")
    scenario.windowSystem.clearRecordedCalls()
    return scenario
  }

  @Test func theWindowsThatDoNotFitWaitParked() async {
    let scenario = await strip()
    #expect(scenario.frame(of: 1) == halves[0])
    #expect(scenario.frame(of: 2) == halves[1])
    #expect(scenario.isParked(3))
    #expect(scenario.workspaces == [1: 1, 2: 1, 3: 1], "a parked window stays on its workspace")
  }

  @Test func focusingAWindowOutOfViewScrollsToIt() async {
    let scenario = await strip()
    await scenario.command("window focus next")
    #expect(scenario.isParked(3), "window 2 was in view already")
    #expect(await scenario.command("window focus next") == .ok)
    #expect(scenario.isParked(1))
    #expect(scenario.frame(of: 2) == halves[0])
    #expect(scenario.frame(of: 3) == halves[1])
    #expect(scenario.focused == 3)
  }

  @Test func clickingAWindowOutOfViewScrollsToIt() async {
    let scenario = await strip()
    await scenario.focus(3)
    #expect(scenario.isParked(1))
    #expect(scenario.frame(of: 3) == halves[1])
  }

  @Test func switchingWorkspacesLeavesWindowsOutOfViewParked() async {
    let scenario = await strip()
    await scenario.command("workspace focus next")
    await scenario.command("workspace focus prev")
    #expect(!scenario.windowSystem.moves.contains { $0.id == WindowID(3) }, "it never moved")
    #expect(scenario.isParked(3))
    #expect(scenario.frame(of: 1) == halves[0])
  }

  @Test func aWindowOutOfViewStaysOnItsWorkspaceBesideAnotherDisplay() async {
    // Window 3 waits out of view at the laptop's left edge, away from the display to the right.
    let scenario = await strip(displays: [FakeDisplays.main, FakeDisplays.right])
    await scenario.command("workspace retile")
    #expect(scenario.workspaces[3] == 1)
    #expect(scenario.isParked(3))
  }

  @Test func tilingOffBringsWindowsOutOfViewBack() async {
    let scenario = await strip()
    await scenario.command("tiling off")
    #expect(scenario.frame(of: 3) == ManagerHarness.originalFrame(index: 2))
    #expect(scenario.frame(of: 1) == halves[0], "windows in view stay")
  }

  @Test func aRestartKeepsTheView() async {
    let scenario = await strip()
    await scenario.focus(3)
    let next = await scenario.restart()
    #expect(next.windowSystem.moves.isEmpty, "every window is already where it belongs")
    await next.command("workspace retile")
    #expect(next.isParked(1))
    #expect(next.frame(of: 3) == halves[1])
  }

  // MARK: - Sizes

  @Test func aFullWindowFillsTheViewAlone() async {
    let scenario = await strip()
    #expect(await scenario.command("window size full") == .message("size full"))
    #expect(scenario.frame(of: 1) == FakeDisplays.main.visibleFrame)
    #expect(scenario.isParked(2))
    #expect(scenario.isParked(3))
  }

  @Test func aQuarterStacksWithTheNextWindow() async {
    let scenario = await strip()
    #expect(await scenario.command("window size quarter") == .message("size quarter"))
    let top = scenario.frame(of: 1)
    #expect(top?.minX == scenario.frame(of: 2)?.minX)
    #expect(top?.maxY == scenario.frame(of: 2)?.minY, "window 2 goes below window 1")
    #expect(scenario.frame(of: 3) == halves[1], "window 3 comes into view beside them")
  }

  @Test func aQuarterWithoutANeighbourIsAnError() async {
    let scenario = await Scenario(openAtStart: spread([1]))
    await scenario.focus(1)
    await scenario.command("layout set strip")
    #expect(
      await scenario.command("window size quarter")
        == .error(
          "a quarter window shares its column with the next or previous window, and neither is free"
        ))
  }

  @Test func nextCyclesTheSize() async {
    let scenario = await strip()
    #expect(await scenario.command("window size next") == .message("size full"))
    #expect(await scenario.command("window size next") == .message("size quarter"))
    #expect(await scenario.command("window size next") == .message("size half"))
  }

  @Test func otherLayoutsKeepTheSizeForTheStrip() async {
    let scenario = await Scenario(openAtStart: spread([1, 2]))
    await scenario.focus(1)
    #expect(
      await scenario.command("window size full")
        == .message("size full (used by the strip layout)"))
    #expect(scenario.frame(of: 1) == halves[0], "tall ignores it")
    await scenario.command("layout set strip")
    #expect(scenario.frame(of: 1) == FakeDisplays.main.visibleFrame)
  }

  @Test func sizeNeedsAFocusedTiledWindow() async {
    let scenario = await Scenario(openAtStart: spread([1, 2]))
    #expect(
      await scenario.command("window size full") == .error("the focused window is not tiled"))
  }

  // MARK: - Scrolling

  /// Windows 1, 2 and 3 in the strip, window 2 focused, and animations of three frames of 16 ms:
  /// two steps, then the final placement.
  private func animated() async -> Scenario {
    let scenario = await Scenario(
      openAtStart: spread([1, 2, 3]), animates: true, slide: .milliseconds(48),
      frameInterval: .milliseconds(16))
    await scenario.focus(2)
    await scenario.command("layout set strip")
    scenario.windowSystem.clearRecordedCalls()
    return scenario
  }

  private func steps(of window: UInt32, in scenario: Scenario) -> [CGFloat] {
    scenario.windowSystem.nudges.filter { $0.id == WindowID(window) }.map(\.origin.x)
  }

  @Test func focusingAWindowOutOfViewSlidesTheStrip() async throws {
    let scenario = await animated()
    let parked = try #require(scenario.frame(of: 3))
    await scenario.start("window focus next")
    #expect(scenario.frame(of: 3)?.origin == parked.origin, "it starts where it is parked")
    await scenario.runUntilQuiet()
    let steps = steps(of: 3, in: scenario)
    #expect(steps.count == 2)
    #expect(steps == steps.sorted(by: >), "it comes in from the right")
    #expect(scenario.harness.everyPositionIsAllowed())
    #expect(scenario.isParked(1))
    #expect(scenario.frame(of: 2) == halves[0])
    #expect(scenario.frame(of: 3) == halves[1])
  }

  @Test func theFocusEventOfAScrollLetsItRunOn() async {
    let scenario = await animated()
    await scenario.start("window focus next")
    scenario.windowSystem.send(.focused(WindowID(3)))
    await scenario.harness.settle()
    #expect(scenario.frame(of: 3) != halves[1], "still sliding")
    await scenario.runUntilQuiet()
    #expect(steps(of: 3, in: scenario).count == 2, "the slide ran on, step by step")
    #expect(scenario.frame(of: 3) == halves[1])
  }

  @Test func clickingAWindowOutOfViewSlidesTheStrip() async {
    let scenario = await animated()
    await scenario.focus(3)
    #expect(!steps(of: 3, in: scenario).isEmpty)
    #expect(scenario.frame(of: 3) == halves[1])
  }
}
