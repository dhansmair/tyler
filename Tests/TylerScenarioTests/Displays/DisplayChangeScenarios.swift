import CoreGraphics
import Testing
import TylerCore
import TylerTestSupport

@testable import TylerServer

/// Displays that come, go or move: the laptop (`main`: windows 1 and 2 on workspace 1, window 9
/// parked on workspace 2) and the external display above it (`secondary`: window 3 on workspace 5).
/// macOS reports each change as a burst; tylerd acts a second after the last one.
@Suite("Several displays: displays that change")
@MainActor
struct DisplayChangeScenarios {
  private let external = FakeDisplays.secondary
  private let displays = FakeDisplays(displays: [FakeDisplays.main, FakeDisplays.secondary])
  private let clock = TestClock()

  private func harness(animator: Animator = .snap) async -> ManagerHarness {
    let harness = ManagerHarness(
      [1, 2, 9],
      extra: [makeWindow(id: 3, frame: CGRect(x: 100, y: -1000, width: 300, height: 200))],
      displays: displays, animator: animator, clock: clock)
    await harness.osFocus(9)
    _ = harness.manager.moveToWorkspace(.number(2), follow: false)
    await harness.osFocus(1)
    harness.windowSystem.clearRecordedCalls()
    return harness
  }

  /// macOS reports the displays as `connected`, then waits for the displays to settle.
  private func change(to connected: [DisplayInfo], in harness: ManagerHarness) async {
    displays.displays = connected
    displays.sendChange()
    await harness.settle()
  }

  private func waitForTheDisplaysToSettle(_ harness: ManagerHarness) async {
    clock.advance(by: WindowManager.displaySettleDelay)
    await harness.settle()
  }

  private func isParked(_ id: UInt32, on display: DisplayInfo, _ harness: ManagerHarness) -> Bool {
    guard let frame = harness.frame(of: id) else { return false }
    return frame == Parking.frame(for: frame, on: display)
  }

  @Test func theWorkspacesOfAnUnpluggedDisplayWaitParkedOnTheLaptop() async {
    let harness = await harness()
    await change(to: [FakeDisplays.main], in: harness)
    // macOS moves the external display's window onto the laptop.
    await harness.windowSystem.userMoves(3, to: CGRect(x: 200, y: 200, width: 800, height: 600))
    #expect(harness.windowSystem.moves.isEmpty, "nothing moves before the displays settle")

    await waitForTheDisplaysToSettle(harness)
    #expect(harness.manager.rows.keys == [FakeDisplays.main.key])
    #expect(harness.manager.rows[0].numbers == [1, 2, 3, 4, 5, 6, 7, 8])
    #expect(harness.workspaces() == [1: 1, 2: 1, 3: 5, 9: 2])
    #expect(harness.isParked(3))
    #expect(harness.frame(of: 1) == TallLayout().frames(count: 2, in: harness.area)[0])
  }

  /// The Mac locks the screen as it sleeps, and macOS shows no windows until it is unlocked.
  @Test func displaysThatSettleAtTheLockScreenArePlacedOnceItIsUnlocked() async {
    let harness = await harness()
    harness.screenLock.isLocked = true
    await change(to: [FakeDisplays.main], in: harness)
    await harness.windowSystem.userMoves(3, to: CGRect(x: 200, y: 200, width: 800, height: 600))
    await waitForTheDisplaysToSettle(harness)
    clock.advance(by: WindowManager.unlockCheckInterval)
    await harness.settle()
    #expect(harness.windowSystem.moves.isEmpty, "nothing moves while the screen is locked")

    harness.screenLock.isLocked = false
    clock.advance(by: WindowManager.unlockCheckInterval)
    await harness.settle()
    #expect(harness.workspaces() == [1: 1, 2: 1, 3: 5, 9: 2])
    #expect(harness.isParked(3))
    #expect(harness.frame(of: 1) == TallLayout().frames(count: 2, in: harness.area)[0])
  }

  @Test func aReconnectedDisplayShowsItsWorkspaceAgain() async {
    let harness = await harness()
    await change(to: [FakeDisplays.main], in: harness)
    await waitForTheDisplaysToSettle(harness)

    await change(to: [FakeDisplays.main, external], in: harness)
    await waitForTheDisplaysToSettle(harness)
    #expect(harness.manager.rows.keys == [FakeDisplays.main.key, external.key])
    #expect(harness.manager.rows[1].number(at: harness.manager.rows[1].currentIndex) == 5)
    #expect(harness.frame(of: 3) == external.visibleFrame)
    #expect(harness.isParked(9))
  }

  /// Each window's move back onto the external display is reported on its own; until then the
  /// others still read as on the laptop and must not join its workspace.
  @Test func severalWindowsGoBackToAReconnectedDisplayTogether() async {
    let harness = ManagerHarness(
      [1],
      extra: [3, 4].map {
        makeWindow(id: $0, frame: CGRect(x: 100 * CGFloat($0), y: -1000, width: 300, height: 200))
      },
      displays: displays, clock: clock)
    await change(to: [FakeDisplays.main], in: harness)
    await waitForTheDisplaysToSettle(harness)

    await change(to: [FakeDisplays.main, external], in: harness)
    await waitForTheDisplaysToSettle(harness)
    #expect(harness.workspaces() == [1: 1, 3: 5, 4: 5])
    #expect(harness.frame(of: 1) == harness.area)
    #expect(harness.frame(of: 3) == TallLayout().frames(count: 2, in: external.visibleFrame)[0])
  }

  @Test func withTheLidClosedTheExternalDisplayTakesTheLaptopsWorkspacesParked() async {
    let harness = await harness()
    // In clamshell mode the external display is the main display, at the origin, with the Dock.
    let alone = DisplayInfo(
      id: external.id, key: external.key, frame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
      visibleFrame: CGRect(x: 55, y: 30, width: 2505, height: 1410))
    await change(to: [alone], in: harness)
    await waitForTheDisplaysToSettle(harness)

    #expect(harness.manager.rows.keys == [external.key])
    #expect(harness.manager.rows[0].number(at: harness.manager.rows[0].currentIndex) == 5)
    #expect(harness.frame(of: 3) == alone.visibleFrame)
    #expect([1, 2, 9].allSatisfy { isParked($0, on: alone, harness) })
  }

  @Test func theListsHoldStillWhileTheDisplaysChange() async {
    let harness = await harness()
    await change(to: [FakeDisplays.main, external], in: harness)
    // Mid-change, the external display's window shows up on the laptop for a moment.
    await harness.windowSystem.userMoves(3, to: CGRect(x: 200, y: 200, width: 800, height: 600))
    #expect(harness.workspaces()[3] == 5, "it doesn't join the laptop's workspace")

    await waitForTheDisplaysToSettle(harness)
    #expect(harness.frame(of: 3) == external.visibleFrame, "it goes back to its slot")
  }

  @Test func aParkedWindowThatMacOSPulledBackIsParkedAgain() async {
    let harness = await harness()
    await change(to: [FakeDisplays.main, external], in: harness)
    await harness.windowSystem.userMoves(9, to: CGRect(x: 1139, y: 100, width: 300, height: 200))
    await waitForTheDisplaysToSettle(harness)
    #expect(harness.isParked(9))
  }

  @Test func movingTheExternalDisplayToTheRightMovesTheLaptopsParkedWindowsToItsLeftEdge() async {
    let harness = await harness()
    let toTheRight = DisplayInfo(
      id: external.id, key: external.key,
      frame: CGRect(x: 1800, y: -271, width: 2560, height: 1440),
      visibleFrame: CGRect(x: 1800, y: -241, width: 2560, height: 1410))
    await change(to: [FakeDisplays.main, toTheRight], in: harness)
    await waitForTheDisplaysToSettle(harness)
    #expect(harness.frame(of: 9)?.maxX == harness.area.minX + 1)
    #expect(harness.isParked(9))
    #expect(harness.frame(of: 3) == toTheRight.visibleFrame)
  }

  @Test func aBurstOfChangesIsActedOnOnceASecondAfterTheLast() async {
    let harness = await harness()
    let moved = DisplayInfo(
      id: external.id, key: external.key, frame: external.frame.offsetBy(dx: 100, dy: 0),
      visibleFrame: external.visibleFrame.offsetBy(dx: 100, dy: 0))
    await change(to: [FakeDisplays.main, moved], in: harness)
    clock.advance(by: .milliseconds(600))
    await change(to: [FakeDisplays.main, moved], in: harness)
    clock.advance(by: .milliseconds(600))
    await harness.settle()
    #expect(harness.windowSystem.moves.isEmpty, "the second change restarted the wait")

    clock.advance(by: .milliseconds(400))
    await harness.settle()
    #expect(harness.frame(of: 3) == moved.visibleFrame)
  }

  @Test func aChangeDuringASlideEndsTheSlide() async {
    let slideClock = TestClock()
    let animator = Animator(
      duration: .milliseconds(48), frameInterval: .milliseconds(16), clock: slideClock)
    let harness = await harness(animator: animator)
    _ = harness.manager.switchWorkspace(.next)
    await harness.settle()
    #expect(harness.manager.slide != nil, "the slide is still running")

    await change(to: [FakeDisplays.main], in: harness)
    await waitForTheDisplaysToSettle(harness)
    #expect(harness.manager.slide == nil)
    #expect([1, 2, 3].allSatisfy(harness.isParked))
    #expect(harness.frame(of: 9) == harness.area)
  }

  @Test func withTilingOffTheWorkspacesFollowButNoWindowMoves() async {
    let harness = await harness()
    _ = harness.manager.setTiling(.off)
    harness.windowSystem.clearRecordedCalls()
    await change(to: [FakeDisplays.main], in: harness)
    await waitForTheDisplaysToSettle(harness)
    #expect(harness.manager.rows.keys == [FakeDisplays.main.key])
    #expect(harness.windowSystem.moves.isEmpty)
  }
}
