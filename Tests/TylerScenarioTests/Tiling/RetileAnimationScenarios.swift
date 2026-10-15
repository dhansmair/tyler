import CoreGraphics
import Testing
import TylerConfig
import TylerCore
import TylerTestSupport

@testable import TylerServer

/// The windows that stay sliding into their new slots over `animations.retile` when one leaves
/// the workspace. Tall with window 1 the main one and 2 and 3 stacked.
@Suite("Tiling: re-tile animation")
@MainActor
struct RetileAnimationScenarios {
  private func scenario(
    retile milliseconds: Int = 250, layout: LayoutKind = .tall
  ) async -> Scenario {
    var config = Config()
    config.animations.retile = milliseconds
    let scenario = await Scenario(
      workspaces: [1: [1, 2, 3]], layout: layout, config: config, animates: true)
    scenario.harness.windowSystem.clearRecordedCalls()
    return scenario
  }

  private func moved(_ scenario: Scenario) -> Bool {
    let windowSystem = scenario.harness.windowSystem
    return !windowSystem.frameSteps.isEmpty || !windowSystem.nudges.isEmpty
  }

  @Test func closingAWindowSlidesTheOthersIntoTheirNewSlots() async throws {
    let scenario = await scenario()
    let bottom = scenario.rect(.rightBottom)
    let right = scenario.rect(.rightHalf)
    await scenario.focus(2)
    scenario.harness.windowSystem.clearRecordedCalls()

    await scenario.command("window close")

    let steps = scenario.harness.windowSystem.frameSteps.filter { $0.id == WindowID(3) }
      .map(\.frame)
    #expect(steps.contains { right.minY < $0.minY && $0.minY < bottom.minY }, "between the slots")
    #expect(steps.allSatisfy { right.minY <= $0.minY && $0.minY <= bottom.minY })
    #expect(zip(steps, steps.dropFirst()).allSatisfy { $0.height <= $1.height }, "growing")
    #expect(scenario.frame(of: 3) == right)
    #expect(scenario.frame(of: 1) == scenario.rect(.leftHalf))
    #expect(
      !scenario.harness.windowSystem.frameSteps.contains { $0.id == WindowID(1) },
      "its slot stays")
  }

  @Test func aWindowItsAppClosesSlidesTheOthersToo() async {
    let scenario = await scenario()
    scenario.harness.windowSystem.windows.removeAll { $0.id == WindowID(2) }
    scenario.harness.windowSystem.send(.destroyed(WindowID(2)))
    await scenario.runUntilQuiet()

    #expect(moved(scenario))
    #expect(scenario.frame(of: 3) == scenario.rect(.rightHalf))
  }

  @Test func aZeroDurationRetilesAtOnce() async {
    let scenario = await scenario(retile: 0)
    await scenario.focus(2)
    scenario.harness.windowSystem.clearRecordedCalls()

    await scenario.command("window close")

    #expect(!moved(scenario))
    #expect(scenario.frame(of: 3) == scenario.rect(.rightHalf))
  }

  @Test func inTheStripTheOthersJump() async {
    let scenario = await scenario(layout: .strip)
    await scenario.focus(2)
    scenario.harness.windowSystem.clearRecordedCalls()

    await scenario.command("window close")

    #expect(!moved(scenario))
  }

  @Test func aNewWindowMakesTheOthersJump() async {
    let scenario = await scenario()
    let window = makeWindow(id: 9, frame: CGRect(x: 700, y: 100, width: 300, height: 200))
    scenario.harness.windowSystem.windows.append(window)
    scenario.harness.windowSystem.send(.created(window))
    await scenario.runUntilQuiet()

    #expect(scenario.list(1).contains(9))
    #expect(!moved(scenario))
  }
}
