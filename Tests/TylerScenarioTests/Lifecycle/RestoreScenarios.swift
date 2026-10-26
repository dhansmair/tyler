import CoreGraphics
import Testing
import TylerCore
import TylerTestSupport

@testable import TylerServer

// MARK: - Restore on exit

@Suite("Restore on exit")
@MainActor
struct RestoreScenarios {
  private let opened = CGRect(x: 700, y: 300, width: 500, height: 400)

  @Test func tiledWindowsGoBackToTheirOriginalFrames() async {
    let scenario = await Scenario(openAtStart: spread([1, 2, 3]))
    #expect(scenario.frame(of: 1) != ManagerHarness.originalFrame(index: 0))
    await scenario.stop()
    for index in 0..<3 {
      #expect(scenario.frame(of: UInt32(index + 1)) == ManagerHarness.originalFrame(index: index))
    }
    #expect(scenario.windowSystem.stopCount == 1)
  }

  @Test func parkedWindowsComeBackToo() async {
    let scenario = await Scenario(openAtStart: spread([1, 2]))
    await scenario.command("workspace focus next")
    await scenario.stop()
    #expect(scenario.frame(of: 1) == ManagerHarness.originalFrame(index: 0))
    #expect(scenario.frame(of: 2) == ManagerHarness.originalFrame(index: 1))
  }

  @Test func windowsOpenedLaterAreRestoredToWhereTheyOpened() async {
    let scenario = await Scenario(openAtStart: spread([1]))
    await scenario.open(makeWindow(id: 9, frame: opened))
    #expect(scenario.frame(of: 9) != opened)
    await scenario.stop()
    #expect(scenario.frame(of: 9) == opened)
  }

  @Test func closedAndFailingWindowsDoNotStopTheRest() async {
    let scenario = await Scenario(openAtStart: spread([1, 2, 3]))
    await scenario.close(2)
    scenario.windowSystem.failingMoves = [WindowID(1)]
    scenario.windowSystem.clearRecordedCalls()
    await scenario.stop()
    #expect(scenario.windowSystem.moves.map(\.id) == [WindowID(3)])
    #expect(scenario.frame(of: 3) == ManagerHarness.originalFrame(index: 2))
    #expect(scenario.windowSystem.stopCount == 1)
  }

  @Test func aReusedWindowIDGoesBackToWhereTheNewWindowOpened() async {
    let scenario = await Scenario(openAtStart: spread([1, 2]))
    await scenario.close(2)
    // Window ids can be reused; the old window's frame must not come back with the id.
    await scenario.open(makeWindow(id: 2, frame: opened))
    #expect(scenario.frame(of: 2) != opened)
    await scenario.stop()
    #expect(scenario.frame(of: 2) == opened)
  }

  @Test func aStateHandedOverLeavesOutWindowsThatClosedInBetween() async {
    let scenario = await Scenario(openAtStart: spread([1, 2]))
    // Window 2 closed, and another app's new window took its id before the next tylerd started.
    let next = await scenario.restart(closing: [2])
    var newcomer = makeWindow(id: 2, frame: opened)
    newcomer.processID = 501
    await next.open(newcomer)
    await next.stop()
    #expect(next.frame(of: 2) == opened)
    #expect(next.frame(of: 1) == ManagerHarness.originalFrame(index: 0))
  }

  @Test func windowsTylerdNeverMovedAreLeftAlone() async {
    let scenario = await Scenario(openAtStart: spread([1]) + [makeWindow(id: 7, kind: .dialog)])
    await scenario.stop()
    #expect(!scenario.windowSystem.moves.contains { $0.id == WindowID(7) })
  }

  @Test func aSlideInProgressIsAbandonedAndEverythingRestored() async {
    let scenario = await Scenario(
      openAtStart: spread([1, 2]), animates: true, slide: .milliseconds(48),
      frameInterval: .milliseconds(16))
    await scenario.start("workspace focus next")
    await scenario.wait(.milliseconds(16))
    await scenario.stop()
    await scenario.wait(.milliseconds(100))
    #expect(scenario.frame(of: 1) == ManagerHarness.originalFrame(index: 0))
    #expect(scenario.frame(of: 2) == ManagerHarness.originalFrame(index: 1))
  }

  @Test func stoppingBeforeStartingMovesNothing() async {
    let scenario = await Scenario(
      openAtStart: [makeWindow(id: 1)], gate: FakeGate(isTrusted: false))
    await scenario.stop()
    #expect(scenario.windowSystem.moves.isEmpty)
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

  @Test func windowsLeftParkedByACrashAreTiledAgain() async {
    let scenario = await Scenario(openAtStart: Self.leftParked())
    #expect(!scenario.isParked(1))
    #expect(scenario.frame(of: 1).map(scenario.rect(.full).contains) == true)
  }

  @Test func stoppingBringsWindowsLeftParkedByACrashIntoView() async {
    let scenario = await Scenario(openAtStart: Self.leftParked())
    await scenario.stop()
    let parked = Parking.frame(
      for: ManagerHarness.originalFrame(index: 0), on: FakeDisplays.main)
    #expect(scenario.frame(of: 1) == Parking.pulledIn(parked, on: FakeDisplays.main))
    #expect(scenario.frame(of: 2) == ManagerHarness.originalFrame(index: 1))
  }
}
