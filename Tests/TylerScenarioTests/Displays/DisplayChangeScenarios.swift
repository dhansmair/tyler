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
  private let displays = [FakeDisplays.main, FakeDisplays.secondary]

  private func scenario() async -> Scenario {
    let scenario = await Scenario(
      displays: displays, workspaces: [1: [1, 2], 2: [9], 5: [3]])
    await scenario.focus(1)
    scenario.windowSystem.clearRecordedCalls()
    return scenario
  }

  private func isParked(_ id: UInt32, on display: DisplayInfo, _ scenario: Scenario) -> Bool {
    guard let frame = scenario.frame(of: id) else { return false }
    return frame == Parking.frame(for: frame, on: display)
  }

  @Test func theWorkspacesOfAnUnpluggedDisplayWaitParkedOnTheLaptop() async {
    let scenario = await scenario()
    await scenario.beginDisplayChange(to: [FakeDisplays.main])
    // macOS moves the external display's window onto the laptop.
    await scenario.windowSystem.userMoves(3, to: CGRect(x: 200, y: 200, width: 800, height: 600))
    #expect(scenario.windowSystem.moves.isEmpty, "nothing moves before the displays settle")

    await scenario.wait(WindowManager.displaySettleDelay)
    #expect(scenario.rows == [[1, 2, 3, 4, 5, 6, 7, 8]])
    #expect(scenario.workspaces == [1: 1, 2: 1, 3: 5, 9: 2])
    #expect(scenario.isParked(3))
    #expect(scenario.frame(of: 1) == scenario.rect(.leftHalf))
  }

  /// The Mac locks the screen as it sleeps, and macOS shows no windows until it is unlocked.
  @Test func displaysThatSettleAtTheLockScreenArePlacedOnceItIsUnlocked() async {
    let scenario = await scenario()
    scenario.screenLock.isLocked = true
    await scenario.beginDisplayChange(to: [FakeDisplays.main])
    await scenario.windowSystem.userMoves(3, to: CGRect(x: 200, y: 200, width: 800, height: 600))
    await scenario.wait(WindowManager.displaySettleDelay)
    await scenario.wait(WindowManager.unlockCheckInterval)
    #expect(scenario.windowSystem.moves.isEmpty, "nothing moves while the screen is locked")

    scenario.screenLock.isLocked = false
    await scenario.wait(WindowManager.unlockCheckInterval)
    #expect(scenario.workspaces == [1: 1, 2: 1, 3: 5, 9: 2])
    #expect(scenario.isParked(3))
    #expect(scenario.frame(of: 1) == scenario.rect(.leftHalf))
  }

  @Test func aReconnectedDisplayShowsItsWorkspaceAgain() async {
    let scenario = await scenario()
    await scenario.changeDisplays(to: [FakeDisplays.main])

    await scenario.changeDisplays(to: displays)
    #expect(scenario.rows == [[1, 2, 3, 4], [5, 6, 7, 8]])
    #expect(scenario.shown == [1, 5])
    #expect(scenario.frame(of: 3) == scenario.rect(.full, display: 2))
    #expect(scenario.isParked(9))
  }

  /// Each window's move back onto the external display is reported on its own; until then the
  /// others still read as on the laptop and must not join its workspace.
  @Test func severalWindowsGoBackToAReconnectedDisplayTogether() async {
    let scenario = await Scenario(displays: displays, workspaces: [1: [1], 5: [3, 4]])
    await scenario.changeDisplays(to: [FakeDisplays.main])

    await scenario.changeDisplays(to: displays)
    #expect(scenario.workspaces == [1: 1, 3: 5, 4: 5])
    #expect(scenario.frame(of: 1) == scenario.rect(.full))
    #expect(scenario.frame(of: 3) == scenario.rect(.leftHalf, display: 2))
  }

  @Test func withTheLidClosedTheExternalDisplayTakesTheLaptopsWorkspacesParked() async {
    let scenario = await scenario()
    // In clamshell mode the external display is the main display, at the origin, with the Dock.
    let alone = DisplayInfo(
      id: external.id, key: external.key, frame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
      visibleFrame: CGRect(x: 55, y: 30, width: 2505, height: 1410))
    await scenario.changeDisplays(to: [alone])

    #expect(scenario.rows == [[1, 2, 3, 4, 5, 6, 7, 8]], "one display holds them all")
    #expect(scenario.shown == [5])
    #expect(scenario.frame(of: 3) == alone.visibleFrame)
    #expect([1, 2, 9].allSatisfy { isParked($0, on: alone, scenario) })
  }

  @Test func theListsHoldStillWhileTheDisplaysChange() async {
    let scenario = await scenario()
    await scenario.beginDisplayChange(to: displays)
    // Mid-change, the external display's window shows up on the laptop for a moment.
    await scenario.windowSystem.userMoves(3, to: CGRect(x: 200, y: 200, width: 800, height: 600))
    #expect(scenario.workspaces[3] == 5, "it doesn't join the laptop's workspace")

    await scenario.wait(WindowManager.displaySettleDelay)
    #expect(scenario.frame(of: 3) == scenario.rect(.full, display: 2), "it goes back to its slot")
  }

  @Test func aParkedWindowThatMacOSPulledBackIsParkedAgain() async {
    let scenario = await scenario()
    await scenario.beginDisplayChange(to: displays)
    await scenario.windowSystem.userMoves(9, to: CGRect(x: 1139, y: 100, width: 300, height: 200))
    await scenario.wait(WindowManager.displaySettleDelay)
    #expect(scenario.isParked(9))
  }

  @Test func movingTheExternalDisplayToTheRightMovesTheLaptopsParkedWindowsToItsLeftEdge() async {
    let scenario = await scenario()
    let toTheRight = DisplayInfo(
      id: external.id, key: external.key,
      frame: CGRect(x: 1800, y: -271, width: 2560, height: 1440),
      visibleFrame: CGRect(x: 1800, y: -241, width: 2560, height: 1410))
    await scenario.changeDisplays(to: [FakeDisplays.main, toTheRight])
    #expect(scenario.frame(of: 9)?.maxX == scenario.rect(.full).minX + 1)
    #expect(scenario.isParked(9))
    #expect(scenario.frame(of: 3) == toTheRight.visibleFrame)
  }

  @Test func aBurstOfChangesIsActedOnOnceASecondAfterTheLast() async {
    let scenario = await scenario()
    let moved = DisplayInfo(
      id: external.id, key: external.key, frame: external.frame.offsetBy(dx: 100, dy: 0),
      visibleFrame: external.visibleFrame.offsetBy(dx: 100, dy: 0))
    await scenario.beginDisplayChange(to: [FakeDisplays.main, moved])
    await scenario.wait(.milliseconds(600))
    await scenario.beginDisplayChange(to: [FakeDisplays.main, moved])
    await scenario.wait(.milliseconds(600))
    #expect(scenario.windowSystem.moves.isEmpty, "the second change restarted the wait")

    await scenario.wait(.milliseconds(400))
    #expect(scenario.frame(of: 3) == moved.visibleFrame)
  }

  @Test func aChangeDuringASlideEndsTheSlide() async {
    // A slide much longer than the wait for the displays, so only the change can end it.
    let scenario = await Scenario(
      displays: displays, workspaces: [1: [1, 2], 2: [9], 5: [3]], animates: true,
      slide: .seconds(10), frameInterval: .milliseconds(16))
    await scenario.start("workspace focus next")
    await scenario.wait(.milliseconds(16))
    #expect(!scenario.isParked(1), "the slide is still running")

    await scenario.beginDisplayChange(to: [FakeDisplays.main])
    await scenario.wait(WindowManager.displaySettleDelay)
    #expect([1, 2, 3].allSatisfy(scenario.isParked))
    #expect(scenario.frame(of: 9) == scenario.rect(.full))
  }

  @Test func withTilingOffTheWorkspacesFollowButNoWindowMoves() async {
    let scenario = await scenario()
    await scenario.command("tiling off")
    scenario.windowSystem.clearRecordedCalls()
    await scenario.changeDisplays(to: [FakeDisplays.main])
    #expect(scenario.rows.count == 1)
    #expect(scenario.windowSystem.moves.isEmpty)
  }
}
