import CoreGraphics
import Testing
import TylerCore
import TylerTestSupport

@testable import TylerServer

/// The steps of a slide don't wait for the apps: the real window system queues them per app, and they
/// land late, or not at all when a newer one replaces them. Here the fake holds every step until
/// the test releases it, so whatever ends a slide runs while its steps are still on their way. A
/// window must end up where the last placement put it, never where a late step would.
@Suite("Queued moves")
@MainActor
struct QueuedMovesScenarios {
  /// Four frames of 16 ms: three steps, then the final placement.
  private let clock = TestClock()
  private var animator: Animator {
    Animator(duration: .milliseconds(64), frameInterval: .milliseconds(16), clock: clock)
  }

  /// Window 1 on workspace 1, on screen; window 2 on workspace 2, parked. Moves are held from
  /// here on.
  private func makeHarness() async -> ManagerHarness {
    let harness = ManagerHarness([1, 2], animator: animator, clock: clock)
    await harness.osFocus(2)
    _ = harness.manager.moveToWorkspace(.next, follow: false)
    await runAnimations(harness)
    harness.windowSystem.holdsMoves = true
    harness.windowSystem.clearRecordedCalls()
    return harness
  }

  private func nextFrame(_ harness: ManagerHarness) async {
    await harness.settle()
    clock.advance(by: .milliseconds(16))
    await harness.settle()
  }

  private func runAnimations(_ harness: ManagerHarness) async {
    await harness.settle()
    while clock.hasSleepers {
      clock.advance(by: .milliseconds(16))
      await harness.settle()
    }
  }

  /// The steps still held land now, as late as an app could take them.
  private func landLateSteps(_ harness: ManagerHarness) async {
    harness.windowSystem.releaseHeldMoves()
    await harness.settle()
  }

  @Test func aFinishedSlideLeavesNoStepToLand() async {
    let harness = await makeHarness()
    _ = harness.manager.switchWorkspace(.next)
    await nextFrame(harness)
    #expect(!harness.windowSystem.heldMoves.isEmpty, "the first step is on its way")

    await runAnimations(harness)
    #expect(harness.windowSystem.heldMoves.isEmpty, "the final placement dropped what was left")
    await landLateSteps(harness)
    #expect(harness.frame(of: 2) == harness.area)
    #expect(harness.isParked(1))
  }

  @Test func aCommandInTheMiddleOfASlideHasTheLastWord() async {
    let harness = await makeHarness()
    _ = harness.manager.switchWorkspace(.next)
    await nextFrame(harness)
    await nextFrame(harness)
    _ = harness.manager.switchWorkspace(.prev)
    await runAnimations(harness)

    await landLateSteps(harness)
    #expect(harness.frame(of: 1) == harness.area)
    #expect(harness.isParked(2))
  }

  @Test func retilingInTheMiddleOfASlidePutsEveryWindowInItsSlot() async {
    let harness = await makeHarness()
    _ = harness.manager.switchWorkspace(.next)
    await nextFrame(harness)
    _ = harness.manager.retile()
    await runAnimations(harness)

    await landLateSteps(harness)
    #expect(harness.frame(of: 2) == harness.area)
    #expect(harness.isParked(1))
  }

  @Test func stoppingInTheMiddleOfASlidePutsEveryWindowBack() async {
    let harness = await makeHarness()
    _ = harness.manager.switchWorkspace(.next)
    await nextFrame(harness)
    harness.manager.stop()
    await harness.settle()

    await landLateSteps(harness)
    #expect(harness.frame(of: 1) == ManagerHarness.originalFrame(index: 0))
    #expect(harness.frame(of: 2) == ManagerHarness.originalFrame(index: 1))
  }
}
