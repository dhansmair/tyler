import CoreGraphics
import Testing
import TylerConfig
import TylerCore
import TylerTestSupport

@testable import TylerServer

/// Tall with window 1 the main one and 2 and 3 stacked, then 1 swapped with the next.
@Suite("Tiling: swap animation")
@MainActor
struct SwapAnimationScenarios {
  private let clock = TestClock()

  private func harness(swap milliseconds: Int) async -> ManagerHarness {
    var config = Config()
    config.animations.swap = milliseconds
    let harness = ManagerHarness(
      [1, 2, 3], animator: Animator(frameInterval: .milliseconds(16), clock: clock),
      config: config, clock: clock)
    await harness.osFocus(1)
    await runAnimations(harness)
    harness.backend.clearRecordedCalls()
    return harness
  }

  private func runAnimations(_ harness: ManagerHarness) async {
    await harness.settle()
    while clock.hasSleepers {
      clock.advance(by: .milliseconds(16))
      await harness.settle()
    }
  }

  @Test func theSwappedWindowsSlideIntoEachOthersSlotsChangingSize() async throws {
    let harness = await harness(swap: 48)
    let main = try #require(harness.frame(of: 1))
    let top = try #require(harness.frame(of: 2))
    let bottom = harness.frame(of: 3)

    _ = harness.manager.swap(.next)
    await runAnimations(harness)

    let steps = harness.backend.frameSteps.filter { $0.id == WindowID(2) }.map(\.frame)
    #expect(steps.count == 2)
    #expect(steps.allSatisfy { main.minX < $0.minX && $0.minX < top.minX }, "between the slots")
    #expect(
      steps.allSatisfy { top.height < $0.height && $0.height < main.height },
      "growing on the way")
    #expect(harness.frame(of: 1) == top)
    #expect(harness.frame(of: 2) == main)
    #expect(harness.frame(of: 3) == bottom)
    #expect(!harness.backend.frameSteps.contains { $0.id == WindowID(3) }, "its slot stays")
    #expect(harness.backend.nudges.isEmpty, "both windows change size")
  }

  @Test func aZeroDurationSwapsAtOnce() async throws {
    let harness = await harness(swap: 0)
    let main = try #require(harness.frame(of: 1))
    let top = try #require(harness.frame(of: 2))

    _ = harness.manager.swap(.next)

    #expect(harness.frame(of: 1) == top)
    #expect(harness.frame(of: 2) == main)
    await runAnimations(harness)
    #expect(harness.backend.nudges.isEmpty)
  }
}
