import CoreGraphics
import Testing
import TylerConfig
import TylerCore
import TylerProtocol
import TylerTestSupport

@testable import TylerServer

/// Tiling: commands, driven through a fake backend.
@Suite("Tiling: commands")
@MainActor
struct TilingCommandScenarios {
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

  @Test func layoutNextLeavesOutTheStripByDefault() {
    let harness = ManagerHarness([1, 2])
    let names = (1...3).map { _ in harness.manager.setLayout(.next) }
    #expect(names == ["grid", "full", "tall"].map { .message("layout \($0)") })
  }

  @Test func layoutNextFollowsTheConfiguredCycle() {
    let config = Config(layouts: Config.Layouts(cycle: [.strip, .tall]))
    let harness = ManagerHarness([1, 2], config: config)
    #expect(harness.manager.setLayout(.next) == .message("layout strip"))
    #expect(harness.manager.setLayout(.next) == .message("layout tall"))
    // A layout chosen by name, outside the cycle, goes on to the cycle's first.
    _ = harness.manager.setLayout(.set(.full))
    #expect(harness.manager.setLayout(.next) == .message("layout strip"))
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
    #expect(harness.manager.setFloat(.toggle) == .ok)
    #expect(harness.manager.slots == [1: 1, 3: 2])
    let floatedWindow = harness.manager.listed.first { $0.id == WindowID(2) }
    #expect(floatedWindow?.isFloated == true)
    #expect(floatedWindow?.slot == nil)
  }

  @Test func aFloatedWindowIsNotMovedByLaterRetiles() async {
    let harness = ManagerHarness([1, 2, 3])
    harness.backend.send(.focused(WindowID(2)))
    await settle()
    _ = harness.manager.setFloat(.toggle)
    harness.backend.clearRecordedCalls()
    _ = harness.manager.retile()
    #expect(!harness.backend.moves.map(\.id.rawValue).contains(2))
  }

  @Test func floatingTwiceTilesTheWindowAgain() async {
    let harness = ManagerHarness([1, 2])
    harness.backend.send(.focused(WindowID(2)))
    await settle()
    _ = harness.manager.setFloat(.toggle)
    #expect(harness.manager.slots == [1: 1])
    // A floated window can still be focused by the user and toggled back.
    #expect(harness.manager.setFloat(.toggle) == .ok)
    #expect(harness.manager.slots == [1: 1, 2: 2])
  }

  @Test func floatOnAndOffSetTheStateWhateverItWas() async {
    let harness = ManagerHarness([1, 2])
    harness.backend.send(.focused(WindowID(2)))
    await settle()
    #expect(harness.manager.setFloat(.on) == .ok)
    #expect(harness.manager.slots == [1: 1])
    #expect(harness.manager.setFloat(.on) == .message("already floating"))
    #expect(harness.manager.slots == [1: 1])
    #expect(harness.manager.setFloat(.off) == .ok)
    #expect(harness.manager.slots == [1: 1, 2: 2])
    #expect(harness.manager.setFloat(.off) == .message("already tiled"))
    #expect(harness.manager.slots == [1: 1, 2: 2])
  }

  @Test(arguments: FloatMode.allCases)
  func windowsThatAreNeverTiledCannotBeFloatedOrTiled(mode: FloatMode) async {
    let harness = ManagerHarness(windows: spread([1]) + [makeWindow(id: 8, kind: .dialog)])
    harness.backend.send(.focused(WindowID(8)))
    await settle()
    #expect(
      harness.manager.setFloat(mode)
        == .error("this window is never tiled, so it can't be floated"))
  }

  @Test func floatNeedsAFocusedWindow() {
    let harness = ManagerHarness([1, 2])
    #expect(harness.manager.setFloat(.toggle) == .error("no focused window"))
  }

  @Test func aDestroyedWindowIsForgottenByTheFloatedSet() async {
    let harness = ManagerHarness([1, 2])
    harness.backend.send(.focused(WindowID(2)))
    await settle()
    _ = harness.manager.setFloat(.toggle)
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
      harness.manager.setFloat(.toggle),
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
    let window = makeWindow(id: 9, frame: CGRect(x: 700, y: 100, width: 300, height: 200))
    harness.backend.windows.append(window)
    harness.backend.send(.created(window))
    await settle()
    harness.backend.clearRecordedCalls()

    #expect(harness.manager.setTiling(.on) == .message("tiling on"))
    #expect(harness.manager.slots.count == 3)
    #expect(!harness.backend.moves.isEmpty)
  }

  @Test func turningTilingOnSaysWhichWindowsItCouldNotPlace() {
    let harness = ManagerHarness([1, 2])
    _ = harness.manager.setTiling(.off)
    harness.backend.failingMoves = [WindowID(2)]
    #expect(harness.manager.setTiling(.on) == .message("tiling on; 1 window could not be placed"))
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
      backend: FakeWindowSystem(), displays: FakeDisplays(), gate: FakeGate(isTrusted: false))
    let expected = Response.error(WindowManager.permissionMessage)
    #expect(manager.retile() == expected)
    #expect(manager.focus(.next) == expected)
    #expect(manager.swap(.next) == expected)
    #expect(manager.setLayout(.next) == expected)
    #expect(manager.adjustRatio(by: 0.05) == expected)
    #expect(manager.setFloat(.toggle) == expected)
  }

  @Test(arguments: [(TilingMode.on, "tiling on"), (.off, "tiling off")])
  func tilingWithoutPermissionSaysItWaits(mode: TilingMode, reply: String) {
    let manager = WindowManager(
      backend: FakeWindowSystem(), displays: FakeDisplays(), gate: FakeGate(isTrusted: false))
    let expected =
      "\(reply) once Accessibility permission is granted\n\(WindowManager.permissionMessage)"
    #expect(manager.setTiling(mode) == .message(expected))
  }

  @Test func tilingOffBeforePermissionLeavesWindowsAloneOnceGranted() {
    let gate = FakeGate(isTrusted: false)
    let harness = ManagerHarness(windows: spread([1, 2]), gate: gate)
    _ = harness.manager.setTiling(.off)
    gate.isTrusted = true
    #expect(harness.manager.startIfPermitted())
    #expect(harness.backend.moves.isEmpty)
    #expect(harness.manager.tilingStatus == .off)
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
