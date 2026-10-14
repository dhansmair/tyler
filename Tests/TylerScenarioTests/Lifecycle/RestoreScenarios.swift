import CoreGraphics
import Testing
import TylerCore
import TylerTestSupport

@testable import TylerServer

// MARK: - Restore on exit

@Suite("Restore on exit")
@MainActor
struct RestoreScenarios {
  @Test func tiledWindowsGoBackToTheirOriginalFrames() {
    let harness = ManagerHarness([1, 2, 3])
    #expect(harness.frame(of: 1) != ManagerHarness.originalFrame(index: 0))
    harness.manager.stop()
    for index in 0..<3 {
      #expect(harness.frame(of: UInt32(index + 1)) == ManagerHarness.originalFrame(index: index))
    }
    #expect(harness.windowSystem.stopCount == 1)
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
    harness.windowSystem.windows.append(makeWindow(id: 9, frame: opened))
    harness.windowSystem.send(.created(makeWindow(id: 9, frame: opened)))
    await harness.settle()
    #expect(harness.frame(of: 9) != opened)
    harness.manager.stop()
    #expect(harness.frame(of: 9) == opened)
  }

  @Test func closedAndFailingWindowsDoNotStopTheRest() async {
    let harness = ManagerHarness([1, 2, 3])
    harness.windowSystem.windows.removeAll { $0.id == WindowID(2) }
    harness.windowSystem.send(.destroyed(WindowID(2)))
    await harness.settle()
    harness.windowSystem.failingMoves = [WindowID(1)]
    harness.windowSystem.clearRecordedCalls()
    harness.manager.stop()
    #expect(harness.windowSystem.moves.map(\.id) == [WindowID(3)])
    #expect(harness.frame(of: 3) == ManagerHarness.originalFrame(index: 2))
    #expect(harness.windowSystem.stopCount == 1)
  }

  @Test func aReusedWindowIDGoesBackToWhereTheNewWindowOpened() async {
    let harness = ManagerHarness([1, 2])
    harness.windowSystem.windows.removeAll { $0.id == WindowID(2) }
    harness.windowSystem.send(.destroyed(WindowID(2)))
    await harness.settle()
    // Window ids can be reused; the old window's frame must not come back with the id.
    let opened = CGRect(x: 700, y: 300, width: 500, height: 400)
    harness.windowSystem.windows.append(makeWindow(id: 2, frame: opened))
    harness.windowSystem.send(.created(makeWindow(id: 2, frame: opened)))
    await harness.settle()
    #expect(harness.frame(of: 2) != opened)
    harness.manager.stop()
    #expect(harness.frame(of: 2) == opened)
  }

  @Test func aStateHandedOverLeavesOutWindowsThatClosedInBetween() async {
    let harness = ManagerHarness([1, 2])
    let saved = harness.manager.handOver()
    // Window 2 closed, and another app's new window took its id before the next tylerd started.
    let opened = CGRect(x: 700, y: 300, width: 500, height: 400)
    let successor = harness.successor(saved: saved, closing: [2])
    let windowSystem = successor.windowSystem
    var newcomer = makeWindow(id: 2, frame: opened)
    newcomer.processID = 501
    windowSystem.windows.append(newcomer)
    windowSystem.send(.created(newcomer))
    await settle()
    successor.manager.stop()
    #expect(windowSystem.frame(of: 2) == opened)
    #expect(windowSystem.frame(of: 1) == ManagerHarness.originalFrame(index: 0))
  }

  @Test func windowsTylerdNeverMovedAreLeftAlone() {
    let harness = ManagerHarness([1], extra: [makeWindow(id: 7, kind: .dialog)])
    harness.manager.stop()
    #expect(!harness.windowSystem.moves.contains { $0.id == WindowID(7) })
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
    let windowSystem = FakeWindowSystem(windows: [makeWindow(id: 1)])
    let manager = WindowManager(
      windowSystem: windowSystem, displays: FakeDisplays(), gate: FakeGate(isTrusted: false))
    manager.stop()
    #expect(windowSystem.moves.isEmpty)
  }

  // MARK: - After a crash

  /// Windows parked by a tylerd that crashed, as the next tylerd finds them: window 1 at the
  /// right parking spot, window 2 on screen.
  private static func leftParked() -> [WindowInfo] {
    let frame = ManagerHarness.originalFrame(index: 0)
    return [
      makeWindow(id: 1, frame: Parking.frame(for: frame, on: FakeDisplays.main)),
      makeWindow(id: 2, frame: ManagerHarness.originalFrame(index: 1)),
    ]
  }

  @Test func windowsLeftParkedByACrashAreTiledAgain() {
    let harness = ManagerHarness(windows: Self.leftParked())
    #expect(!harness.isParked(1))
    #expect(harness.frame(of: 1).map(harness.area.contains) == true)
  }

  @Test func stoppingBringsWindowsLeftParkedByACrashIntoView() {
    let harness = ManagerHarness(windows: Self.leftParked())
    harness.manager.stop()
    let parked = Parking.frame(
      for: ManagerHarness.originalFrame(index: 0), on: FakeDisplays.main)
    #expect(harness.frame(of: 1) == Parking.pulledIn(parked, on: FakeDisplays.main))
    #expect(harness.frame(of: 2) == ManagerHarness.originalFrame(index: 1))
  }
}
