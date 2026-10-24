import CoreGraphics
import Testing
import TylerConfig
import TylerCore
import TylerTestSupport

/// Tall with window 1 the main one and 2 and 3 stacked, then 1 swapped with the next.
@Suite("Tiling: swap animation")
@MainActor
struct SwapAnimationScenarios {
  private func scenario(swap milliseconds: Int) async -> Scenario {
    var config = Config()
    config.animations.swap = milliseconds
    let scenario = await Scenario(
      workspaces: [1: [1, 2, 3]], config: config, animates: true,
      frameInterval: .milliseconds(16))
    await scenario.focus(1)
    scenario.windowSystem.clearRecordedCalls()
    return scenario
  }

  @Test func theSwappedWindowsSlideIntoEachOthersSlotsChangingSize() async throws {
    let scenario = await scenario(swap: 48)
    let main = try #require(scenario.frame(of: 1))
    let top = try #require(scenario.frame(of: 2))
    let bottom = scenario.frame(of: 3)

    await scenario.command("window swap next")

    let steps = scenario.windowSystem.frameSteps.filter { $0.id == WindowID(2) }.map(\.frame)
    #expect(steps.count == 2)
    #expect(steps.allSatisfy { main.minX < $0.minX && $0.minX < top.minX }, "between the slots")
    #expect(
      steps.allSatisfy { top.height < $0.height && $0.height < main.height },
      "growing on the way")
    #expect(scenario.frame(of: 1) == top)
    #expect(scenario.frame(of: 2) == main)
    #expect(scenario.frame(of: 3) == bottom)
    #expect(!scenario.windowSystem.frameSteps.contains { $0.id == WindowID(3) }, "its slot stays")
    #expect(scenario.windowSystem.nudges.isEmpty, "both windows change size")
  }

  @Test func aZeroDurationSwapsAtOnce() async throws {
    let scenario = await scenario(swap: 0)
    let main = try #require(scenario.frame(of: 1))
    let top = try #require(scenario.frame(of: 2))

    await scenario.start("window swap next")

    #expect(scenario.frame(of: 1) == top)
    #expect(scenario.frame(of: 2) == main)
    await scenario.runUntilQuiet()
    #expect(scenario.windowSystem.nudges.isEmpty)
  }
}
