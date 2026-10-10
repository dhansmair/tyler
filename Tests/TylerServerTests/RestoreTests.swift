import CoreGraphics
import Testing
import TylerCore

@testable import TylerServer

// MARK: - Restore on exit

@Suite("Restore on exit")
@MainActor
struct RestoreTests {
  @Test func tiledWindowsGoBackToTheirOriginalFrames() {
    let harness = ManagerHarness([1, 2, 3])
    #expect(harness.frame(of: 1) != ManagerHarness.originalFrame(index: 0))
    harness.manager.stop()
    for index in 0..<3 {
      #expect(harness.frame(of: UInt32(index + 1)) == ManagerHarness.originalFrame(index: index))
    }
    #expect(harness.backend.stopCount == 1)
  }

  @Test func parkedWindowsComeBackToo() {
    let harness = ManagerHarness([1, 2])
    _ = harness.manager.switchWorkspace(.next)
    harness.manager.stop()
    #expect(harness.frame(of: 1) == ManagerHarness.originalFrame(index: 0))
    #expect(harness.frame(of: 2) == ManagerHarness.originalFrame(index: 1))
  }

  @Test func windowsOpenedLaterAreRestoredToWhereTheyOpened() async {
    let harness = ManagerHarness([1])
    let opened = CGRect(x: 700, y: 300, width: 500, height: 400)
    harness.backend.windows.append(makeWindow(id: 9, frame: opened))
    harness.backend.send(.created(makeWindow(id: 9, frame: opened)))
    await harness.settle()
    #expect(harness.frame(of: 9) != opened)
    harness.manager.stop()
    #expect(harness.frame(of: 9) == opened)
  }

  @Test func closedAndFailingWindowsDoNotStopTheRest() async {
    let harness = ManagerHarness([1, 2, 3])
    harness.backend.windows.removeAll { $0.id == WindowID(2) }
    harness.backend.send(.destroyed(WindowID(2)))
    await harness.settle()
    harness.backend.failingMoves = [WindowID(1)]
    harness.backend.clearRecordedCalls()
    harness.manager.stop()
    #expect(harness.backend.moves.map(\.id) == [WindowID(3)])
    #expect(harness.frame(of: 3) == ManagerHarness.originalFrame(index: 2))
    #expect(harness.backend.stopCount == 1)
  }

  @Test func aReusedWindowIDGoesBackToWhereTheNewWindowOpened() async {
    let harness = ManagerHarness([1, 2])
    harness.backend.windows.removeAll { $0.id == WindowID(2) }
    harness.backend.send(.destroyed(WindowID(2)))
    await harness.settle()
    // Window ids can be reused; the old window's frame must not come back with the id.
    let opened = CGRect(x: 700, y: 300, width: 500, height: 400)
    harness.backend.windows.append(makeWindow(id: 2, frame: opened))
    harness.backend.send(.created(makeWindow(id: 2, frame: opened)))
    await harness.settle()
    #expect(harness.frame(of: 2) != opened)
    harness.manager.stop()
    #expect(harness.frame(of: 2) == opened)
  }

  @Test func aStateHandedOverLeavesOutWindowsThatClosedInBetween() async {
    let harness = ManagerHarness([1, 2])
    let saved = harness.manager.handOver()
    // Window 2 closed, and a new window took its id before the next tylerd started.
    let opened = CGRect(x: 700, y: 300, width: 500, height: 400)
    let successor = harness.successor(saved: saved, closing: [2])
    let backend = successor.backend
    backend.windows.append(makeWindow(id: 2, frame: opened))
    backend.send(.created(makeWindow(id: 2, frame: opened)))
    await settle()
    successor.manager.stop()
    #expect(backend.frame(of: 2) == opened)
    #expect(backend.frame(of: 1) == ManagerHarness.originalFrame(index: 0))
  }

  @Test func windowsTylerdNeverMovedAreLeftAlone() {
    let harness = ManagerHarness([1], extra: [makeWindow(id: 7, kind: .dialog)])
    harness.manager.stop()
    #expect(!harness.backend.moves.contains { $0.id == WindowID(7) })
  }

  @Test func aSlideInProgressIsAbandonedAndEverythingRestored() async {
    let clock = TestClock()
    let harness = ManagerHarness(
      [1, 2],
      animator: Animator(
        duration: .milliseconds(48), frameInterval: .milliseconds(16), clock: clock))
    _ = harness.manager.switchWorkspace(.next)
    clock.advance(by: .milliseconds(16))
    await harness.settle()
    harness.manager.stop()
    clock.advance(by: .milliseconds(100))
    await harness.settle()
    #expect(harness.frame(of: 1) == ManagerHarness.originalFrame(index: 0))
    #expect(harness.frame(of: 2) == ManagerHarness.originalFrame(index: 1))
  }

  @Test func stoppingBeforeStartingMovesNothing() {
    let backend = FakeBackend(windows: [makeWindow(id: 1)])
    let manager = WindowManager(
      backend: backend, displays: FakeDisplays(), gate: FakeGate(isTrusted: false))
    manager.stop()
    #expect(backend.moves.isEmpty)
  }
}
