import CoreGraphics
import MWMCore
import Testing

@testable import MWMServer

/// Tiling: commands, driven through a fake backend.
@Suite("Tiling: commands")
@MainActor
struct TilingCommandTests {
  private let area = FakeDisplays.main.visibleFrame

  /// A manager with `count` standard windows spread left to right on the primary display,
  /// already started (so the initial tiling has happened) and with recorded calls cleared.
  private func makeStarted(
    windows: [WindowInfo],
    displays: FakeDisplays = FakeDisplays(),
    clearRecordedCalls: Bool = true
  ) -> (WindowManager, FakeBackend) {
    let backend = FakeBackend(windows: windows)
    let manager = WindowManager(
      backend: backend, displays: displays, gate: FakeGate(isTrusted: true))
    manager.startIfPermitted()
    if clearRecordedCalls { backend.clearRecordedCalls() }
    return (manager, backend)
  }

  private func spread(_ ids: UInt32...) -> [WindowInfo] {
    ids.enumerated().map { index, windowID in
      makeWindow(
        id: windowID,
        frame: CGRect(x: 100 + index * 50, y: 100, width: 300, height: 200))
    }
  }

  /// Lets the manager's event-pump task run.
  private func settle() async {
    for _ in 0..<30 { await Task.yield() }
  }

  private func listed(_ manager: WindowManager) -> [WindowInfo] {
    guard case .windows(let windows) = manager.windows() else { return [] }
    return windows
  }

  private func slots(_ manager: WindowManager) -> [UInt32: Int] {
    Dictionary(
      uniqueKeysWithValues: listed(manager).compactMap { window in
        window.slot.map { (window.id.rawValue, $0) }
      })
  }

  private func frame(of windowID: UInt32, in backend: FakeBackend) -> CGRect? {
    backend.windows.first { $0.id.rawValue == windowID }?.frame
  }

  // MARK: - Focus and swap commands

  @Test func focusNextFocusesTheNextTiledWindow() {
    let (manager, backend) = makeStarted(windows: spread(1, 2, 3))
    _ = manager.focus(.main)
    backend.clearRecordedCalls()
    #expect(manager.focus(.next) == .ok)
    #expect(backend.focusCalls == [WindowID(2)])
    #expect(manager.focus(.next) == .ok)
    #expect(backend.focusCalls == [WindowID(2), WindowID(3)])
  }

  @Test func focusWrapsAroundAndCanJumpToTheMain() {
    let (manager, backend) = makeStarted(windows: spread(1, 2, 3))
    _ = manager.focus(.prev)  // nothing focused yet: the last window
    _ = manager.focus(.next)  // wraps to the first
    _ = manager.focus(.prev)  // back to the last
    _ = manager.focus(.main)
    #expect(backend.focusCalls == [WindowID(3), WindowID(1), WindowID(3), WindowID(1)])
  }

  @Test func aFailedFocusIsReportedAsAnError() {
    let (manager, backend) = makeStarted(windows: spread(1, 2))
    backend.failingFocus = [WindowID(1)]
    guard case .error(let message) = manager.focus(.main) else {
      Issue.record("expected an error")
      return
    }
    #expect(message.contains("cannot focus"))
  }

  @Test func focusOnNoTiledWindowsIsAnError() {
    let (manager, _) = makeStarted(windows: [])
    #expect(manager.focus(.next) == .error("no tiled windows"))
  }

  @Test func swapReordersAndRetiles() async {
    let (manager, backend) = makeStarted(windows: spread(1, 2, 3))
    backend.send(.focused(WindowID(1)))
    await settle()
    backend.clearRecordedCalls()

    #expect(manager.swap(.next) == .ok)
    #expect(slots(manager) == [2: 1, 1: 2, 3: 3])
    // Windows 1 and 2 traded slots, so both had to move.
    #expect(Set(backend.moves.map(\.id.rawValue)) == [1, 2])
  }

  @Test func swapMainBringsTheFocusedWindowToTheMainSlot() async {
    let (manager, backend) = makeStarted(windows: spread(1, 2, 3))
    backend.send(.focused(WindowID(3)))
    await settle()
    _ = manager.swap(.main)
    #expect(slots(manager) == [3: 1, 2: 2, 1: 3])
  }

  @Test func swapNeedsTwoWindows() {
    let (manager, _) = makeStarted(windows: spread(1))
    #expect(manager.swap(.next) == .error("need at least two tiled windows to swap"))
  }

  @Test func swapNeedsAFocusedTiledWindow() {
    let (manager, _) = makeStarted(windows: spread(1, 2))
    #expect(manager.swap(.next) == .error("no tiled window is focused"))
  }

  // MARK: - Layout and ratio

  @Test func layoutFullGivesEveryWindowTheWholeArea() {
    let (manager, backend) = makeStarted(windows: spread(1, 2, 3))
    #expect(manager.setLayout(.set(.full)) == .message("layout full"))
    for windowID: UInt32 in [1, 2, 3] {
      #expect(frame(of: windowID, in: backend) == area)
    }
  }

  @Test func layoutNextCyclesBetweenTallAndFull() {
    let (manager, _) = makeStarted(windows: spread(1, 2))
    #expect(manager.setLayout(.next) == .message("layout full"))
    #expect(manager.setLayout(.next) == .message("layout tall"))
  }

  @Test func ratioMovesTheDividerAndStopsAtItsLimit() {
    let (manager, backend) = makeStarted(windows: spread(1, 2))
    let before = frame(of: 1, in: backend)?.width ?? 0
    #expect(manager.adjustRatio(by: 0.1) == .ok)
    #expect((frame(of: 1, in: backend)?.width ?? 0) > before)

    _ = manager.adjustRatio(by: 5)  // clamps to the maximum
    backend.clearRecordedCalls()
    guard case .message(let text) = manager.adjustRatio(by: 0.05) else {
      Issue.record("expected a message at the limit")
      return
    }
    #expect(text.contains("already at its limit"))
    #expect(backend.moves.isEmpty)
  }

  // MARK: - Floating

  @Test func floatingTheFocusedWindowRemovesItFromTheListAndRetilesTheRest() async {
    let (manager, backend) = makeStarted(windows: spread(1, 2, 3))
    backend.send(.focused(WindowID(2)))
    await settle()
    #expect(manager.toggleFloat() == .ok)
    #expect(slots(manager) == [1: 1, 3: 2])
    let floatedWindow = listed(manager).first { $0.id == WindowID(2) }
    #expect(floatedWindow?.isFloated == true)
    #expect(floatedWindow?.slot == nil)
  }

  @Test func aFloatedWindowIsNotMovedByLaterRetiles() async {
    let (manager, backend) = makeStarted(windows: spread(1, 2, 3))
    backend.send(.focused(WindowID(2)))
    await settle()
    _ = manager.toggleFloat()
    backend.clearRecordedCalls()
    _ = manager.retile()
    #expect(!backend.moves.map(\.id.rawValue).contains(2))
  }

  @Test func floatingTwiceTilesTheWindowAgain() async {
    let (manager, backend) = makeStarted(windows: spread(1, 2))
    backend.send(.focused(WindowID(2)))
    await settle()
    _ = manager.toggleFloat()
    #expect(slots(manager) == [1: 1])
    // A floated window can still be focused by the user and toggled back.
    #expect(manager.toggleFloat() == .ok)
    #expect(slots(manager) == [1: 1, 2: 2])
  }

  @Test func floatNeedsAFocusedWindow() {
    let (manager, _) = makeStarted(windows: spread(1, 2))
    #expect(manager.toggleFloat() == .error("no focused window"))
  }

  @Test func windowsThatAreNeverTiledCannotBeFloated() async {
    let (manager, backend) = makeStarted(windows: spread(1) + [makeWindow(id: 8, kind: .dialog)])
    backend.send(.focused(WindowID(8)))
    await settle()
    guard case .error(let message) = manager.toggleFloat() else {
      Issue.record("expected an error")
      return
    }
    #expect(message.contains("never tiled"))
  }

  @Test func aDestroyedWindowIsForgottenByTheFloatedSet() async {
    let (manager, backend) = makeStarted(windows: spread(1, 2))
    backend.send(.focused(WindowID(2)))
    await settle()
    _ = manager.toggleFloat()
    backend.send(.destroyed(WindowID(2)))
    // The window id comes back (ids can be reused); it must tile like a new window.
    backend.send(
      .created(makeWindow(id: 2, frame: CGRect(x: 300, y: 100, width: 300, height: 200))))
    await settle()
    #expect(slots(manager)[2] != nil)
  }

  // MARK: - Tiling on and off

  @Test func tilingOffBlocksEveryWorkspaceCommand() {
    let (manager, _) = makeStarted(windows: spread(1, 2))
    #expect(manager.setTiling(.off) == .message("tiling off"))
    let blocked: [Response] = [
      manager.retile(), manager.focus(.next), manager.swap(.next),
      manager.setLayout(.next), manager.adjustRatio(by: 0.05), manager.toggleFloat(),
    ]
    for response in blocked {
      #expect(response == .error(WindowManager.tilingOffMessage))
    }
  }

  @Test func tilingOffLeavesWindowsAloneWhenThingsChange() async {
    let (manager, backend) = makeStarted(windows: spread(1, 2))
    _ = manager.setTiling(.off)
    backend.send(
      .created(makeWindow(id: 9, frame: CGRect(x: 700, y: 100, width: 300, height: 200))))
    backend.send(.destroyed(WindowID(1)))
    await settle()
    #expect(backend.moves.isEmpty)
  }

  @Test func tilingOffStillAnswersListAndTilingItself() {
    let (manager, _) = makeStarted(windows: spread(1, 2))
    _ = manager.setTiling(.off)
    #expect(!listed(manager).isEmpty)
    #expect(manager.setTiling(.toggle) == .message("tiling on"))
  }

  @Test func turningTilingBackOnTilesEverythingThatIsEligibleNow() async {
    let (manager, backend) = makeStarted(windows: spread(1, 2))
    _ = manager.setTiling(.off)
    backend.send(
      .created(makeWindow(id: 9, frame: CGRect(x: 700, y: 100, width: 300, height: 200))))
    await settle()
    backend.clearRecordedCalls()

    #expect(manager.setTiling(.on) == .message("tiling on"))
    #expect(slots(manager).count == 3)
    #expect(!backend.moves.isEmpty)
  }

  @Test func turningTilingOnWhenAlreadyOnDoesNotMoveAnything() {
    let (manager, backend) = makeStarted(windows: spread(1, 2))
    #expect(manager.setTiling(.on) == .message("tiling on"))
    #expect(backend.moves.isEmpty)
  }

  @Test func turningTilingOnKeepsTheOrderOfWindowsAlreadyInTheList() async {
    let (manager, backend) = makeStarted(windows: spread(1, 2, 3))
    backend.send(.focused(WindowID(3)))
    await settle()
    _ = manager.swap(.main)  // order is now 3, 2, 1
    _ = manager.setTiling(.off)
    _ = manager.setTiling(.on)
    #expect(slots(manager) == [3: 1, 2: 2, 1: 3])
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
    let (manager, _) = makeStarted(windows: spread(1, 2))
    #expect(manager.handle(.ping) == .pong)
    #expect(manager.handle(.tiling(.off)) == .message("tiling off"))
    #expect(manager.handle(.retile) == .error(WindowManager.tilingOffMessage))
    #expect(manager.handle(.tiling(.on)) == .message("tiling on"))
    #expect(manager.handle(.layout(.set(.full))) == .message("layout full"))
    #expect(manager.handle(.ratio(0.05)) == .ok)
  }
}
