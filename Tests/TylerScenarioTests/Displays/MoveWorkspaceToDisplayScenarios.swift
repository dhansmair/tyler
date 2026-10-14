import CoreGraphics
import Testing
import TylerConfig
import TylerCore
import TylerTestSupport

@testable import TylerServer

/// Moving a whole workspace to another display. The laptop (`main`, display 1, workspaces 1 to 4)
/// holds windows 1 and 2 on workspace 1 and window 9 parked on workspace 2; the external display
/// above it (`secondary`, display 2, workspaces 5 to 8) holds windows 3 and 4 on workspace 5.
@Suite("Several displays: tyler workspace move-to-display")
@MainActor
struct MoveWorkspaceToDisplayScenarios {
  private let external = FakeDisplays.secondary
  private let displays = FakeDisplays(displays: [FakeDisplays.main, FakeDisplays.secondary])
  private let clock = TestClock()

  private func onExternal(_ id: UInt32) -> WindowInfo {
    makeWindow(id: id, frame: CGRect(x: 100 + CGFloat(id) * 50, y: -1000, width: 300, height: 200))
  }

  private func harness(config: Config = Config()) async -> ManagerHarness {
    let harness = ManagerHarness(
      [1, 2, 9], extra: [onExternal(3), onExternal(4)], displays: displays, config: config,
      clock: clock)
    await harness.osFocus(9)
    _ = harness.manager.moveToWorkspace(.number(2), follow: false)
    await harness.osFocus(1)
    harness.windowSystem.clearRecordedCalls()
    return harness
  }

  private func numbers(_ harness: ManagerHarness) -> [[Int]] {
    harness.manager.rows.entries.map(\.row.numbers)
  }

  /// The number of the workspace on screen on each display.
  private func current(_ harness: ManagerHarness) -> [Int] {
    harness.manager.rows.entries.map { $0.row.number(at: $0.row.currentIndex) }
  }

  private func isParked(_ id: UInt32, on display: DisplayInfo, _ harness: ManagerHarness) -> Bool {
    guard let frame = harness.frame(of: id) else { return false }
    return frame == Parking.frame(for: frame, on: display)
  }

  @Test func theWorkspaceComesOnScreenThereWithItsWindowsAndTheFocus() async {
    let harness = await harness()
    #expect(
      harness.manager.moveWorkspaceToDisplay(.number(2))
        == .message("moved workspace 1 to display 2"))
    await harness.settle()
    #expect(numbers(harness) == [[2, 3, 4], [1, 5, 6, 7, 8]])
    #expect(current(harness) == [2, 1])
    #expect(
      harness.workspaces() == [1: 1, 2: 1, 3: 5, 4: 5, 9: 2], "every window kept its workspace")
    let slots = TallLayout().frames(count: 2, in: external.visibleFrame)
    #expect(harness.frame(of: 1) == slots[0])
    #expect(harness.frame(of: 2) == slots[1])
    #expect(isParked(3, on: external, harness))
    #expect(isParked(4, on: external, harness))
    #expect(harness.manager.rows.focusedKey == external.key)
    #expect(harness.windowSystem.focusCalls.last == WindowID(1))
  }

  @Test func theDisplayItLeftShowsItsNextWorkspace() async {
    let harness = await harness()
    _ = harness.manager.moveWorkspaceToDisplay(.next)
    await harness.settle()
    #expect(harness.frame(of: 9) == harness.area)
  }

  @Test func itStaysOnItsNewDisplayThroughUnpluggingAndPluggingBackIn() async {
    let harness = await harness()
    _ = harness.manager.moveWorkspaceToDisplay(.number(2))
    await harness.settle()

    await change(to: [FakeDisplays.main], in: harness)
    #expect(numbers(harness) == [[1, 2, 3, 4, 5, 6, 7, 8]])
    await change(to: [FakeDisplays.main, external], in: harness)
    #expect(numbers(harness) == [[2, 3, 4], [1, 5, 6, 7, 8]])
    #expect(current(harness) == [2, 1])
    #expect(harness.frame(of: 1) == TallLayout().frames(count: 2, in: external.visibleFrame)[0])
  }

  @Test func aRestartKeepsItsNewHome() async {
    let harness = await harness()
    _ = harness.manager.moveWorkspaceToDisplay(.number(2))
    await harness.settle()
    let successor = harness.successor(saved: harness.manager.handOver(), displays: displays)
    #expect(successor.manager.rows.homes[1] == .pinned(external.key))
    #expect(successor.manager.rows.entries.map(\.row.numbers) == [[2, 3, 4], [1, 5, 6, 7, 8]])
  }

  /// A window on its way to another display keeps its workspace until it arrives; one whose app
  /// refused the move belongs where it stayed from the next command on.
  @Test func aWindowWhoseAppRefusedTheMoveStaysBehindAtTheNextCommand() async {
    let harness = await harness()
    harness.windowSystem.failingMoves = [WindowID(2)]
    #expect(
      harness.manager.moveWorkspaceToDisplay(.number(2))
        == .message("moved workspace 1 to display 2; 1 window could not be placed"))
    await harness.settle()
    #expect(harness.workspaces()[2] == 1, "held while it might still arrive")

    _ = harness.manager.retile()
    #expect(harness.workspaces()[2] == 2, "it joins the laptop's workspace on screen")
  }

  @Test func aWorkspaceAlreadyThereIsRefused() async {
    let harness = await harness()
    #expect(
      harness.manager.moveWorkspaceToDisplay(.number(1))
        == .error("workspace 1 is already on display 1"))
    #expect(harness.windowSystem.moves.isEmpty)
  }

  @Test func theOnlyWorkspaceOfADisplayCannotLeaveIt() async {
    let harness = await harness(config: Config(workspaces: Config.Workspaces(count: 1)))
    #expect(
      harness.manager.moveWorkspaceToDisplay(.next)
        == .error("workspace 1 is the only one on its display"))
    #expect(harness.windowSystem.moves.isEmpty)
  }

  @Test func aNumberNoDisplayHasIsAnError() async {
    let harness = await harness()
    #expect(
      harness.manager.moveWorkspaceToDisplay(.number(3))
        == .error("display 3 does not exist (use 1 to 2)"))
  }

  @Test func theRequestReachesTheCommand() async {
    let harness = await harness()
    #expect(
      harness.manager.handle(.moveWorkspaceToDisplay(.number(2)))
        == .message("moved workspace 1 to display 2"))
  }

  /// macOS reports the displays as `connected`, and they settle.
  private func change(to connected: [DisplayInfo], in harness: ManagerHarness) async {
    displays.displays = connected
    displays.sendChange()
    await harness.settle()
    clock.advance(by: WindowManager.displaySettleDelay)
    await harness.settle()
  }
}
