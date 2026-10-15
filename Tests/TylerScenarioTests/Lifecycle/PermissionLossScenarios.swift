import Testing
import TylerCore
import TylerTestSupport

@testable import TylerServer

/// macOS can stop all input when a process with an active event tap loses Accessibility, so
/// tylerd lets go of every tap the moment it notices.
@Suite("Losing the Accessibility permission")
@MainActor
struct PermissionLossScenarios {
  private struct Following {
    let harness: ManagerHarness
    let gate: FakeGate
    let pointer: FakePointer
    let clock: TestClock
    let task: Task<Void, Never>

    func stop() async {
      task.cancel()
      await task.value
    }
  }

  /// Windows 1 and 2 on workspace 1, window 3 parked on workspace 2, while tylerd follows the
  /// permission.
  private func following() async -> Following {
    let gate = FakeGate(isTrusted: true)
    let pointer = FakePointer()
    let clock = TestClock()
    let harness = ManagerHarness(
      windows: spread([1, 2, 3]), gate: gate, pointer: pointer, clock: clock)
    await harness.osFocus(3)
    _ = harness.manager.moveToWorkspace(.next, follow: false)
    await harness.settle()
    harness.windowSystem.clearRecordedCalls()
    let manager = harness.manager
    let task = Task { await manager.followPermission(checkingEvery: .seconds(1)) {} }
    await settle()
    return Following(harness: harness, gate: gate, pointer: pointer, clock: clock, task: task)
  }

  @Test func theNextCheckRemovesEveryTapAndLeavesTheWindowsAlone() async {
    let following = await following()
    let frames = following.harness.windowSystem.windows.map(\.frame)

    following.gate.isTrusted = false
    following.clock.advance(by: .seconds(1))
    await settle()

    #expect(following.harness.manager.state == .waitingForPermission)
    #expect(following.pointer.stopCount == 1)
    #expect(following.harness.windowSystem.stopCount == 1)
    #expect(following.harness.windowSystem.moves.isEmpty)
    #expect(following.harness.windowSystem.windows.map(\.frame) == frames)
    await following.stop()
  }

  @Test func theHintFromMacOSActsWithoutWaitingForTheNextCheck() async {
    let following = await following()

    following.gate.isTrusted = false
    following.gate.announceChange()
    await settle()

    #expect(following.harness.manager.state == .waitingForPermission)
    #expect(following.pointer.stopCount == 1)
    await following.stop()
  }

  @Test func itCarriesOnWithTheWorkspacesOnceThePermissionIsBack() async {
    let following = await following()
    following.gate.isTrusted = false
    following.gate.announceChange()
    await settle()

    following.gate.isTrusted = true
    following.gate.announceChange()
    await settle()

    #expect(following.harness.manager.state == .running)
    #expect(following.harness.workspaces() == [1: 1, 2: 1, 3: 2])
    #expect(following.harness.windowSystem.moves.isEmpty, "every window is still where it was")
    await following.stop()
  }

  @Test func whileThePermissionLastsNothingChanges() async {
    let following = await following()

    following.gate.announceChange()
    following.clock.advance(by: .seconds(1))
    await settle()

    #expect(following.harness.manager.state == .running)
    #expect(following.pointer.stopCount == 0)
    await following.stop()
  }
}
