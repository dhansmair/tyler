import Testing
import TylerCore
import TylerTestSupport

@testable import TylerServer

/// A grant can look fine and still not work (a stale entry after an update or a new login), and
/// macOS shows no windows while the screen is locked: tylerd waits instead of tracking nothing,
/// and says why in `tyler status`.
@Suite("Whether tylerd can reach the windows")
@MainActor
struct WindowAccessScenarios {
  private struct Following {
    let harness: ManagerHarness
    let gate: FakeGate
    let clock: TestClock
    let task: Task<Void, Never>

    func stop() async {
      task.cancel()
      await task.value
    }
  }

  /// Windows 1 and 2, with tylerd started behind `gate` and following it.
  private func following(_ gate: FakeGate) async -> Following {
    let clock = TestClock()
    let harness = ManagerHarness(windows: spread([1, 2]), gate: gate, clock: clock)
    let manager = harness.manager
    let task = Task { await manager.followPermission(checkingEvery: .seconds(1)) {} }
    await settle()
    return Following(harness: harness, gate: gate, clock: clock, task: task)
  }

  @Test func refusedCallsKeepTylerdWaitingUntilTheyWork() async {
    let gate = FakeGate(isTrusted: true)
    gate.probe = .refused
    let following = await following(gate)

    #expect(following.harness.manager.state == .waitingForPermission)
    #expect(following.harness.manager.access == .refused)
    #expect(following.harness.windowSystem.startCount == 0)

    gate.probe = .allowed
    following.clock.advance(by: .seconds(1))
    await settle()
    #expect(following.harness.manager.state == .running)
    #expect(following.harness.manager.access == .ok)
    await following.stop()
  }

  @Test func aLockedScreenKeepsTylerdWaitingUntilItIsUnlocked() async {
    let gate = FakeGate(isTrusted: true)
    gate.isScreenLocked = true
    let following = await following(gate)

    #expect(following.harness.manager.access == .screenLocked)
    #expect(following.harness.windowSystem.startCount == 0)

    gate.isScreenLocked = false
    following.clock.advance(by: .seconds(1))
    await settle()
    #expect(following.harness.manager.state == .running)
    await following.stop()
  }

  @Test func losingThePermissionIsWhatStatusSays() async {
    let following = await following(FakeGate(isTrusted: true))

    following.gate.isTrusted = false
    following.clock.advance(by: .seconds(1))
    await settle()
    #expect(following.harness.manager.access == .notTrusted)
    await following.stop()
  }

  @Test func seeingNoneOfTheWindowsOnScreenIsBlind() async {
    let scenario = await Scenario(openAtStart: spread([1, 2]))
    #expect(scenario.access == .ok)

    scenario.stacking.listedWindows = [WindowID(7), WindowID(8)]
    scenario.windowSystem.isAttaching = true
    #expect(scenario.access == .checking, "an app may still answer")
    scenario.windowSystem.isAttaching = false
    #expect(scenario.access == .blind)
  }
}
