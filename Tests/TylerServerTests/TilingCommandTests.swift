import CoreGraphics
import Testing
import TylerCore

@testable import TylerServer

/// Tiling: commands, driven through a fake backend.
@Suite("Tiling: commands")
@MainActor
struct TilingCommandTests {
  private let area = FakeDisplays.main.visibleFrame

  // MARK: - Focus and swap commands

  @Test func focusNextFocusesTheNextTiledWindow() {
    let harness = ManagerHarness([1, 2, 3])
    _ = harness.manager.focus(.main)
    harness.backend.clearRecordedCalls()
    #expect(harness.manager.focus(.next) == .ok)
    #expect(harness.backend.focusCalls == [WindowID(2)])
    #expect(harness.manager.focus(.next) == .ok)
    #expect(harness.backend.focusCalls == [WindowID(2), WindowID(3)])
  }

  @Test func focusWrapsAroundAndCanJumpToTheMain() {
    let harness = ManagerHarness([1, 2, 3])
    _ = harness.manager.focus(.prev)  // nothing focused yet: the last window
    _ = harness.manager.focus(.next)  // wraps to the first
    _ = harness.manager.focus(.prev)  // back to the last
    _ = harness.manager.focus(.main)
    #expect(harness.backend.focusCalls == [WindowID(3), WindowID(1), WindowID(3), WindowID(1)])
  }

  @Test func aFailedFocusIsReportedAsAnError() {
    let harness = ManagerHarness([1, 2])
    harness.backend.failingFocus = [WindowID(1)]
    guard case .error(let message) = harness.manager.focus(.main) else {
      Issue.record("expected an error")
      return
    }
    #expect(message.contains("cannot focus"))
  }

  @Test func focusOnNoTiledWindowsIsAnError() {
    let harness = ManagerHarness(windows: [])
    #expect(harness.manager.focus(.next) == .error("no tiled windows"))
  }

  @Test func swapReordersAndRetiles() async {
    let harness = ManagerHarness([1, 2, 3])
    harness.backend.send(.focused(WindowID(1)))
    await settle()
    harness.backend.clearRecordedCalls()

    #expect(harness.manager.swap(.next) == .ok)
    #expect(harness.manager.slots == [2: 1, 1: 2, 3: 3])
    // Windows 1 and 2 traded slots, so both had to move.
    #expect(Set(harness.backend.moves.map(\.id.rawValue)) == [1, 2])
  }

  @Test func swapMainBringsTheFocusedWindowToTheMainSlot() async {
    let harness = ManagerHarness([1, 2, 3])
    harness.backend.send(.focused(WindowID(3)))
    await settle()
    _ = harness.manager.swap(.main)
    #expect(harness.manager.slots == [3: 1, 2: 2, 1: 3])
  }

  @Test func swapNeedsTwoWindows() {
    let harness = ManagerHarness([1])
    #expect(harness.manager.swap(.next) == .error("need at least two tiled windows to swap"))
  }

  @Test func swapNeedsAFocusedTiledWindow() {
    let harness = ManagerHarness([1, 2])
    #expect(harness.manager.swap(.next) == .error("no tiled window is focused"))
  }

  // MARK: - Layout and ratio

  @Test func layoutFullGivesEveryWindowTheWholeArea() {
    let harness = ManagerHarness([1, 2, 3])
    #expect(harness.manager.setLayout(.set(.full)) == .message("layout full"))
    for windowID: UInt32 in [1, 2, 3] {
      #expect(harness.frame(of: windowID) == area)
    }
  }

  @Test func layoutNextCyclesBetweenTallAndFull() {
    let harness = ManagerHarness([1, 2])
    #expect(harness.manager.setLayout(.next) == .message("layout full"))
    #expect(harness.manager.setLayout(.next) == .message("layout tall"))
  }

  @Test func ratioMovesTheDividerAndStopsAtItsLimit() {
    let harness = ManagerHarness([1, 2])
    let before = harness.frame(of: 1)?.width ?? 0
    #expect(harness.manager.adjustRatio(by: 0.1) == .ok)
    #expect((harness.frame(of: 1)?.width ?? 0) > before)

    _ = harness.manager.adjustRatio(by: 5)  // clamps to the maximum
    harness.backend.clearRecordedCalls()
    guard case .message(let text) = harness.manager.adjustRatio(by: 0.05) else {
      Issue.record("expected a message at the limit")
      return
    }
    #expect(text.contains("already at its limit"))
    #expect(harness.backend.moves.isEmpty)
  }

  // MARK: - Floating

  @Test func floatingTheFocusedWindowRemovesItFromTheListAndRetilesTheRest() async {
    let harness = ManagerHarness([1, 2, 3])
    harness.backend.send(.focused(WindowID(2)))
    await settle()
    #expect(harness.manager.toggleFloat() == .ok)
    #expect(harness.manager.slots == [1: 1, 3: 2])
    let floatedWindow = harness.manager.listed.first { $0.id == WindowID(2) }
    #expect(floatedWindow?.isFloated == true)
    #expect(floatedWindow?.slot == nil)
  }

  @Test func aFloatedWindowIsNotMovedByLaterRetiles() async {
    let harness = ManagerHarness([1, 2, 3])
    harness.backend.send(.focused(WindowID(2)))
    await settle()
    _ = harness.manager.toggleFloat()
    harness.backend.clearRecordedCalls()
    _ = harness.manager.retile()
    #expect(!harness.backend.moves.map(\.id.rawValue).contains(2))
  }

  @Test func floatingTwiceTilesTheWindowAgain() async {
    let harness = ManagerHarness([1, 2])
    harness.backend.send(.focused(WindowID(2)))
    await settle()
    _ = harness.manager.toggleFloat()
    #expect(harness.manager.slots == [1: 1])
    // A floated window can still be focused by the user and toggled back.
    #expect(harness.manager.toggleFloat() == .ok)
    #expect(harness.manager.slots == [1: 1, 2: 2])
  }

  @Test func floatNeedsAFocusedWindow() {
    let harness = ManagerHarness([1, 2])
    #expect(harness.manager.toggleFloat() == .error("no focused window"))
  }

  @Test func windowsThatAreNeverTiledCannotBeFloated() async {
    let harness = ManagerHarness(windows: spread([1]) + [makeWindow(id: 8, kind: .dialog)])
    harness.backend.send(.focused(WindowID(8)))
    await settle()
    guard case .error(let message) = harness.manager.toggleFloat() else {
      Issue.record("expected an error")
      return
    }
    #expect(message.contains("never tiled"))
  }

  @Test func aDestroyedWindowIsForgottenByTheFloatedSet() async {
    let harness = ManagerHarness([1, 2])
    harness.backend.send(.focused(WindowID(2)))
    await settle()
    _ = harness.manager.toggleFloat()
    harness.backend.send(.destroyed(WindowID(2)))
    // The window id comes back (ids can be reused); it must tile like a new window.
    harness.backend.send(
      .created(makeWindow(id: 2, frame: CGRect(x: 300, y: 100, width: 300, height: 200))))
    await settle()
    #expect(harness.manager.slots[2] != nil)
  }

  // MARK: - Tiling on and off

  @Test func tilingOffBlocksEveryWorkspaceCommand() {
    let harness = ManagerHarness([1, 2])
    #expect(harness.manager.setTiling(.off) == .message("tiling off"))
    let blocked: [Response] = [
      harness.manager.retile(), harness.manager.focus(.next), harness.manager.swap(.next),
      harness.manager.setLayout(.next), harness.manager.adjustRatio(by: 0.05),
      harness.manager.toggleFloat(),
    ]
    for response in blocked {
      #expect(response == .error(WindowManager.tilingOffMessage))
    }
  }

  @Test func tilingOffLeavesWindowsAloneWhenThingsChange() async {
    let harness = ManagerHarness([1, 2])
    _ = harness.manager.setTiling(.off)
    harness.backend.send(
      .created(makeWindow(id: 9, frame: CGRect(x: 700, y: 100, width: 300, height: 200))))
    harness.backend.send(.destroyed(WindowID(1)))
    await settle()
    #expect(harness.backend.moves.isEmpty)
  }

  @Test func tilingOffStillAnswersListAndTilingItself() {
    let harness = ManagerHarness([1, 2])
    _ = harness.manager.setTiling(.off)
    #expect(!harness.manager.listed.isEmpty)
    #expect(harness.manager.setTiling(.toggle) == .message("tiling on"))
  }

  @Test func turningTilingBackOnTilesEverythingThatIsEligibleNow() async {
    let harness = ManagerHarness([1, 2])
    _ = harness.manager.setTiling(.off)
    harness.backend.send(
      .created(makeWindow(id: 9, frame: CGRect(x: 700, y: 100, width: 300, height: 200))))
    await settle()
    harness.backend.clearRecordedCalls()

    #expect(harness.manager.setTiling(.on) == .message("tiling on"))
    #expect(harness.manager.slots.count == 3)
    #expect(!harness.backend.moves.isEmpty)
  }

  @Test func turningTilingOnWhenAlreadyOnDoesNotMoveAnything() {
    let harness = ManagerHarness([1, 2])
    #expect(harness.manager.setTiling(.on) == .message("tiling on"))
    #expect(harness.backend.moves.isEmpty)
  }

  @Test func turningTilingOnKeepsTheOrderOfWindowsAlreadyInTheList() async {
    let harness = ManagerHarness([1, 2, 3])
    harness.backend.send(.focused(WindowID(3)))
    await settle()
    _ = harness.manager.swap(.main)  // order is now 3, 2, 1
    _ = harness.manager.setTiling(.off)
    _ = harness.manager.setTiling(.on)
    #expect(harness.manager.slots == [3: 1, 2: 2, 1: 3])
  }

  // MARK: - Permission

  @Test func commandsWithoutPermissionExplainWhatToDo() {
    let manager = WindowManager(
      backend: FakeBackend(), displays: FakeDisplays(), gate: FakeGate(isTrusted: false))
    let expected = Response.error(WindowManager.permissionMessage)
    #expect(manager.retile() == expected)
    #expect(manager.focus(.next) == expected)
    #expect(manager.swap(.next) == expected)
    #expect(manager.setLayout(.next) == expected)
    #expect(manager.adjustRatio(by: 0.05) == expected)
    #expect(manager.toggleFloat() == expected)
  }

  @Test func handleRoutesEveryRequestToTheRightCommand() {
    let harness = ManagerHarness([1, 2])
    #expect(harness.manager.handle(.ping) == .pong)
    #expect(harness.manager.handle(.tiling(.off)) == .message("tiling off"))
    #expect(harness.manager.handle(.retile) == .error(WindowManager.tilingOffMessage))
    #expect(harness.manager.handle(.tiling(.on)) == .message("tiling on"))
    #expect(harness.manager.handle(.layout(.set(.full))) == .message("layout full"))
    #expect(harness.manager.handle(.ratio(0.05)) == .ok)
  }
}
