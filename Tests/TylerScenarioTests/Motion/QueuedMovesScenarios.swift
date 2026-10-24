import CoreGraphics
import Testing
import TylerCore
import TylerTestSupport

/// The steps of a slide don't wait for the apps: the real window system queues them per app, and
/// they land late, or not at all when a newer one replaces them. Here the fake holds every step
/// until the test releases it, so whatever ends a slide runs while its steps are still on their
/// way. A window must end up where the last placement put it, never where a late step would.
@Suite("Queued moves")
@MainActor
struct QueuedMovesScenarios {
  private let frame = Duration.milliseconds(16)

  /// Window 1 on workspace 1, on screen; window 2 on workspace 2, parked from its slot. Slides
  /// take four frames of 16 ms: three steps, then the final placement. Moves are held from here
  /// on.
  private func scenario() async -> Scenario {
    let scenario = await Scenario(
      openAtStart: spread([1, 2]), animates: true, slide: .milliseconds(64),
      frameInterval: frame)
    await scenario.focus(2)
    await scenario.command("window move-to-workspace next")
    scenario.windowSystem.holdsMoves = true
    scenario.windowSystem.clearRecordedCalls()
    return scenario
  }

  /// The steps still held land now, as late as an app could take them.
  private func landLateSteps(_ scenario: Scenario) async {
    scenario.windowSystem.releaseHeldMoves()
    await scenario.harness.settle()
  }

  @Test func aFinishedSlideLeavesNoStepToLand() async {
    let scenario = await scenario()
    await scenario.start("workspace focus next")
    await scenario.wait(frame)
    #expect(!scenario.windowSystem.heldMoves.isEmpty, "the first step is on its way")

    await scenario.runUntilQuiet()
    #expect(scenario.windowSystem.heldMoves.isEmpty, "the final placement dropped what was left")
    await landLateSteps(scenario)
    #expect(scenario.frame(of: 2) == scenario.rect(.full))
    #expect(scenario.isParked(1))
  }

  @Test func aCommandInTheMiddleOfASlideHasTheLastWord() async {
    let scenario = await scenario()
    await scenario.start("workspace focus next")
    await scenario.wait(frame)
    await scenario.wait(frame)
    await scenario.command("workspace focus prev")

    await landLateSteps(scenario)
    #expect(scenario.frame(of: 1) == scenario.rect(.full))
    #expect(scenario.isParked(2))
  }

  @Test func retilingInTheMiddleOfASlidePutsEveryWindowInItsSlot() async {
    let scenario = await scenario()
    await scenario.start("workspace focus next")
    await scenario.wait(frame)
    await scenario.command("workspace retile")

    await landLateSteps(scenario)
    #expect(scenario.frame(of: 2) == scenario.rect(.full))
    #expect(scenario.isParked(1))
  }

  @Test func stoppingInTheMiddleOfASlidePutsEveryWindowBack() async {
    let scenario = await scenario()
    await scenario.start("workspace focus next")
    await scenario.wait(frame)
    await scenario.stop()

    await landLateSteps(scenario)
    #expect(scenario.frame(of: 1) == ManagerHarness.originalFrame(index: 0))
    #expect(scenario.frame(of: 2) == ManagerHarness.originalFrame(index: 1))
  }
}
