import CoreGraphics
import Testing
import TylerConfig
import TylerCore
import TylerTestSupport

@testable import TylerServer

/// `window float` moving the window between its slot and its floated frame over
/// `animations.retile`, along with the windows that make room. Window 2 is on the right of 1.
@Suite("Tiling: float animation")
@MainActor
struct FloatAnimationScenarios {
  private func scenario(
    retile milliseconds: Int = 250, layout: LayoutKind = .tall
  ) async -> Scenario {
    var config = Config()
    config.animations.retile = milliseconds
    let scenario = await Scenario(
      workspaces: [1: [1, 2]], layout: layout, config: config, animates: true)
    await scenario.focus(2)
    scenario.harness.windowSystem.clearRecordedCalls()
    return scenario
  }

  private func steps(of window: UInt32, in scenario: Scenario) -> [CGRect] {
    scenario.harness.windowSystem.frameSteps.filter { $0.id == WindowID(window) }.map(\.frame)
  }

  private func floatedFrame(in scenario: Scenario) -> CGRect {
    FloatedFrame.frame(leaving: scenario.rect(.rightHalf), in: scenario.rect(.full))
  }

  @Test func floatingSlidesTheWindowTowardTheMiddle() async {
    let scenario = await scenario()
    let slot = scenario.rect(.rightHalf)
    let floated = floatedFrame(in: scenario)

    await scenario.command("window float on")

    let steps = steps(of: 2, in: scenario)
    #expect(steps.contains { slot.minY < $0.minY && $0.minY < floated.minY }, "between the two")
    #expect(zip(steps, steps.dropFirst()).allSatisfy { $0.height >= $1.height }, "shrinking")
    #expect(steps.allSatisfy { $0.width == slot.width }, "only along the axis it spans")
    #expect(scenario.frame(of: 2) == floated)
    #expect(!self.steps(of: 1, in: scenario).isEmpty, "the other window slides too")
    #expect(scenario.frame(of: 1) == scenario.rect(.full))
  }

  @Test func tilingAgainSlidesTheWindowIntoItsSlot() async {
    let scenario = await scenario()
    await scenario.command("window float on")
    scenario.harness.windowSystem.clearRecordedCalls()

    await scenario.command("window float off")

    #expect(!steps(of: 2, in: scenario).isEmpty)
    #expect(!steps(of: 1, in: scenario).isEmpty)
    #expect(scenario.frame(of: 2) == scenario.rect(.rightHalf))
    #expect(scenario.frame(of: 1) == scenario.rect(.leftHalf))
  }

  @Test func aZeroDurationMovesTheWindowAtOnce() async {
    let scenario = await scenario(retile: 0)

    await scenario.command("window float on")

    #expect(steps(of: 2, in: scenario).isEmpty)
    #expect(scenario.frame(of: 2) == floatedFrame(in: scenario))
  }

  @Test func inTheStripTheWindowStaysWhereItIs() async {
    let scenario = await scenario(layout: .strip)
    let before = scenario.frame(of: 2)

    await scenario.command("window float on")

    #expect(steps(of: 2, in: scenario).isEmpty)
    #expect(scenario.frame(of: 2) == before)
  }
}
