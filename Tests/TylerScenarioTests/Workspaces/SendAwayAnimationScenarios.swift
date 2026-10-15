import CoreGraphics
import Testing
import TylerConfig
import TylerCore
import TylerTestSupport

@testable import TylerServer

/// `window move-to-workspace` without `--follow`: the window sent away slides off while the
/// windows that stay slide into their new slots, over `animations.retile`. Tall with window 1
/// the main one and 2 and 3 stacked; 3 is sent to the next workspace.
@Suite("Workspaces: sending a window away animates the rest")
@MainActor
struct SendAwayAnimationScenarios {
  private func sendingThird(
    retile milliseconds: Int = 250, displays: [DisplayInfo] = [FakeDisplays.main]
  ) async -> Scenario {
    var config = Config()
    config.animations.retile = milliseconds
    let scenario = await Scenario(
      displays: displays, workspaces: [1: [1, 2, 3]], config: config, animates: true)
    await scenario.focus(3)
    scenario.harness.windowSystem.clearRecordedCalls()
    await scenario.command("window move-to-workspace next")
    return scenario
  }

  private func steps(of window: UInt32, in scenario: Scenario) -> [CGRect] {
    scenario.harness.windowSystem.frameSteps.filter { $0.id == WindowID(window) }.map(\.frame)
  }

  private func nudges(of window: UInt32, in scenario: Scenario) -> [CGPoint] {
    scenario.harness.windowSystem.nudges.filter { $0.id == WindowID(window) }.map(\.origin)
  }

  @Test func theOthersSlideIntoTheirNewSlotsWhileTheWindowLeaves() async {
    let scenario = await sendingThird()
    let top = scenario.rect(.rightTop)
    let right = scenario.rect(.rightHalf)

    let growing = steps(of: 2, in: scenario)
    #expect(growing.contains { top.height < $0.height && $0.height < right.height })
    #expect(scenario.frame(of: 2) == right)
    #expect(!nudges(of: 3, in: scenario).isEmpty, "the window sent away slides off")
    #expect(scenario.isParked(3))
    #expect(scenario.frame(of: 1) == scenario.rect(.leftHalf))
    #expect(steps(of: 1, in: scenario).isEmpty, "its slot stays")
  }

  @Test func aZeroDurationMakesTheOthersJump() async {
    let scenario = await sendingThird(retile: 0)

    #expect(steps(of: 2, in: scenario).isEmpty)
    #expect(scenario.frame(of: 2) == scenario.rect(.rightHalf))
    #expect(!nudges(of: 3, in: scenario).isEmpty, "the window sent away still slides off")
    #expect(scenario.isParked(3))
  }

  @Test func besideADisplayToTheRightTheWindowJumpsAndTheOthersStillSlide() async {
    let scenario = await sendingThird(displays: [FakeDisplays.main, FakeDisplays.right])

    #expect(nudges(of: 3, in: scenario).isEmpty, "sent off by a jump")
    #expect(scenario.isParked(3))
    #expect(!steps(of: 2, in: scenario).isEmpty)
    #expect(scenario.frame(of: 2) == scenario.rect(.rightHalf))
  }
}
