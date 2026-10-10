import CoreGraphics
import Testing
import TylerCore

@testable import TylerServer

/// Shared setup for the workspace, move-to-workspace and restore suites.
@MainActor
struct WorkspaceHarness {
  let manager: WindowManager
  let backend: FakeBackend
  let display = FakeDisplays.main
  var area: CGRect { display.visibleFrame }

  /// Windows `ids` spread left to right on the primary display, started and with recorded calls
  /// cleared. The default animator snaps; pass one with a `TestClock` to step slides.
  init(
    _ ids: [UInt32],
    extra: [WindowInfo] = [],
    displays: FakeDisplays = FakeDisplays(),
    animator: Animator = .snap,
    config: Config = Config(),
    configFile: FakeConfigFile? = nil,
    pointer: FakePointer? = nil,
    clock: any Clock<Duration> = ContinuousClock()
  ) {
    backend = FakeBackend(windows: Self.spread(ids) + extra)
    manager = WindowManager(
      backend: backend, displays: displays, gate: FakeGate(isTrusted: true), animator: animator,
      config: config, configSource: configFile?.source, pointer: pointer, clock: clock)
    manager.startIfPermitted()
    backend.clearRecordedCalls()
  }

  static func spread(_ ids: [UInt32]) -> [WindowInfo] {
    ids.enumerated().map { index, windowID in
      makeWindow(id: windowID, frame: originalFrame(index: index))
    }
  }

  static func originalFrame(index: Int) -> CGRect {
    CGRect(x: 100 + index * 50, y: 100, width: 300, height: 200)
  }

  /// Lets the manager's event-pump task (and any animation task) run.
  func settle() async {
    for _ in 0..<30 { await Task.yield() }
  }

  func frame(of windowID: UInt32) -> CGRect? {
    backend.windows.first { $0.id.rawValue == windowID }?.frame
  }

  func isParked(_ windowID: UInt32) -> Bool {
    guard let frame = frame(of: windowID) else { return false }
    return frame == Parking.frame(for: frame, on: display)
  }

  /// Whether macOS would accept every position tylerd asked for without pulling the window
  /// back on screen (see `Parking`).
  func everyPositionIsAllowed() -> Bool {
    let positions =
      backend.moves.map { ($0.id, $0.frame.origin) } + backend.nudges.map { ($0.id, $0.origin) }
    return positions.allSatisfy { windowID, origin in
      guard let width = frame(of: windowID.rawValue)?.width else { return false }
      return Parking.allowedX(width: width, on: display).contains(origin.x)
        && origin.y >= display.visibleFrame.minY
    }
  }

  /// Window id → 1-based workspace, for windows on a workspace.
  func workspaces() -> [UInt32: Int] {
    guard case .windows(let windows) = manager.windows() else { return [:] }
    return Dictionary(
      uniqueKeysWithValues: windows.compactMap { window in
        window.workspace.map { (window.id.rawValue, $0) }
      })
  }

  /// Focuses `windowID` the way the OS would, and waits for the manager to see it.
  func osFocus(_ windowID: UInt32) async {
    backend.send(.focused(WindowID(windowID)))
    await settle()
  }
}

// MARK: - Switching

@Suite("Workspaces: switching")
@MainActor
struct WorkspaceSwitchTests {
  @Test func existingWindowsStartOnTheFirstWorkspace() {
    let harness = WorkspaceHarness([1, 2])
    #expect(harness.workspaces() == [1: 1, 2: 1])
  }

  @Test func switchingParksTheCurrentWindowsAndGivesNoFocusToAnEmptyWorkspace() {
    let harness = WorkspaceHarness([1, 2])
    #expect(harness.manager.switchWorkspace(.next) == .message("workspace 2"))
    #expect(harness.isParked(1))
    #expect(harness.isParked(2))
    #expect(harness.workspaces() == [1: 1, 2: 1], "parked windows keep their workspace")
    #expect(harness.backend.focusCalls.isEmpty)
    #expect(harness.backend.unfocusCount == 0, "no window had focus")
  }

  @Test func switchingToAnEmptyWorkspaceTakesFocusFromTheParkedWindow() async {
    let harness = WorkspaceHarness([1, 2])
    await harness.osFocus(2)
    _ = harness.manager.switchWorkspace(.next)
    #expect(harness.isParked(2))
    #expect(harness.backend.focusCalls.isEmpty)
    #expect(harness.backend.unfocusCount == 1)
  }

  @Test func failingToTakeFocusStillSwitches() async {
    let harness = WorkspaceHarness([1])
    await harness.osFocus(1)
    harness.backend.isUnfocusFailing = true
    #expect(harness.manager.switchWorkspace(.next) == .message("workspace 2"))
    #expect(harness.isParked(1))
    #expect(harness.backend.unfocusCount == 1)
  }

  @Test func newWindowsOpenOnTheCurrentWorkspace() async {
    let harness = WorkspaceHarness([1, 2])
    _ = harness.manager.switchWorkspace(.number(3))
    harness.backend.windows.append(makeWindow(id: 9))
    harness.backend.send(.created(makeWindow(id: 9)))
    await harness.settle()
    #expect(harness.workspaces() == [1: 1, 2: 1, 9: 3])
    #expect(harness.frame(of: 9) == harness.area)
  }

  @Test func switchingBackRestoresTheSlotsAndFocusesTheFocusedWindow() async {
    let harness = WorkspaceHarness([1, 2])
    let slots = [harness.frame(of: 1), harness.frame(of: 2)]
    await harness.osFocus(2)
    _ = harness.manager.switchWorkspace(.next)
    _ = harness.manager.switchWorkspace(.prev)
    #expect([harness.frame(of: 1), harness.frame(of: 2)] == slots)
    #expect(harness.backend.focusCalls == [WindowID(2)])
  }

  @Test(arguments: [
    (WorkspaceTarget.next, 4, "workspace 1"), (.prev, 1, "workspace 4"),
    (.number(2), 1, "workspace 2"),
  ])
  func upAndDownWrapAtTheEnds(target: WorkspaceTarget, from: Int, expected: String) {
    let harness = WorkspaceHarness([1])
    _ = harness.manager.switchWorkspace(.number(from))
    #expect(harness.manager.switchWorkspace(target) == .message(expected))
  }

  @Test(arguments: [5, 0])
  func aWorkspaceOutOfRangeIsAnError(number: Int) {
    let harness = WorkspaceHarness([1])
    #expect(
      harness.manager.switchWorkspace(.number(number))
        == .error("workspace \(number) does not exist (use 1 to 4)"))
    #expect(harness.backend.moves.isEmpty)
  }

  @Test func switchingToTheCurrentWorkspaceMovesNothing() {
    let harness = WorkspaceHarness([1, 2])
    #expect(harness.manager.switchWorkspace(.number(1)) == .message("workspace 1"))
    #expect(harness.backend.moves.isEmpty)
  }

  @Test func switchingNeedsTilingAndPermission() {
    let harness = WorkspaceHarness([1])
    _ = harness.manager.setTiling(.off)
    #expect(harness.manager.switchWorkspace(.next) == .error(WindowManager.tilingOffMessage))
    #expect(
      harness.manager.moveToWorkspace(.next, follow: false)
        == .error(WindowManager.tilingOffMessage))

    let waiting = WindowManager(
      backend: FakeBackend(), displays: FakeDisplays(), gate: FakeGate(isTrusted: false))
    #expect(waiting.switchWorkspace(.next) == .error(WindowManager.permissionMessage))
  }

  @Test func handleRoutesTheWorkspaceRequests() async {
    let harness = WorkspaceHarness([1, 2])
    await harness.osFocus(2)
    #expect(
      harness.manager.handle(.moveToWorkspace(.number(3), follow: false))
        == .message("moved to workspace 3"))
    #expect(harness.manager.handle(.workspace(.number(3))) == .message("workspace 3"))
    #expect(harness.workspaces() == [1: 1, 2: 3])
  }

  @Test func tilingOffBringsParkedWindowsBackAndForgetsTheirWorkspace() {
    let harness = WorkspaceHarness([1, 2, 3])
    _ = harness.manager.switchWorkspace(.next)
    harness.backend.windows.append(makeWindow(id: 9))
    _ = harness.manager.setTiling(.off)
    #expect(harness.frame(of: 1) == WorkspaceHarness.originalFrame(index: 0))
    #expect(harness.frame(of: 3) == WorkspaceHarness.originalFrame(index: 2))
    #expect(harness.workspaces().isEmpty)
  }

  @Test func turningTilingBackOnTilesEverythingOntoTheCurrentWorkspace() {
    let harness = WorkspaceHarness([1, 2])
    _ = harness.manager.switchWorkspace(.next)
    _ = harness.manager.setTiling(.off)
    _ = harness.manager.setTiling(.on)
    #expect(harness.workspaces() == [1: 2, 2: 2])
  }

  @Test func aParkedWindowThatClosesLeavesItsWorkspace() async {
    let harness = WorkspaceHarness([1, 2])
    _ = harness.manager.switchWorkspace(.next)
    harness.backend.send(.destroyed(WindowID(1)))
    await harness.settle()
    #expect(harness.workspaces() == [2: 1])
  }

  @Test func aParkedWindowStaysOnItsWorkspaceWhateverItsFrameSays() async {
    let displays = FakeDisplays(displays: [FakeDisplays.main, FakeDisplays.secondary])
    let harness = WorkspaceHarness([1, 2], displays: displays)
    _ = harness.manager.switchWorkspace(.next)
    // macOS (or the user) moves a parked window onto the other display.
    harness.backend.send(
      .updated(makeWindow(id: 1, frame: CGRect(x: 2000, y: 100, width: 300, height: 200))))
    await harness.settle()
    #expect(harness.workspaces() == [1: 1, 2: 1])
  }

  @Test func parkedWindowsOverlappingAnotherDisplayComeBackWithTheirWorkspace() async {
    // A tall display to the right: a window parked in the primary's corner overlaps it more
    // than the primary, so by frame alone it would count as being on that display.
    let tall = DisplayInfo(
      id: 3,
      frame: CGRect(x: 1800, y: 0, width: 1920, height: 2400),
      visibleFrame: CGRect(x: 1800, y: 0, width: 1920, height: 2400))
    let harness = WorkspaceHarness(
      [1, 2], displays: FakeDisplays(displays: [FakeDisplays.main, tall]))
    let slots = [harness.frame(of: 1), harness.frame(of: 2)]
    _ = harness.manager.switchWorkspace(.next)
    await harness.settle()  // the manager learns the parked frames
    _ = harness.manager.switchWorkspace(.prev)
    #expect(harness.workspaces() == [1: 1, 2: 1])
    #expect([harness.frame(of: 1), harness.frame(of: 2)] == slots)
  }

  @Test func aParkedWindowThatIsMinimizedComesBackOnTheCurrentWorkspace() async {
    let harness = WorkspaceHarness([1, 2])
    _ = harness.manager.switchWorkspace(.next)
    harness.backend.send(.updated(makeWindow(id: 1, isMinimized: true)))
    await harness.settle()
    #expect(harness.workspaces() == [2: 1])
    harness.backend.send(.updated(makeWindow(id: 1)))
    await harness.settle()
    #expect(harness.workspaces() == [1: 2, 2: 1])
  }

  @Test func floatedWindowsBelongToNoWorkspaceAndAreNeverParked() async {
    let harness = WorkspaceHarness([1, 2])
    await harness.osFocus(2)
    _ = harness.manager.toggleFloat()
    let floatedFrame = harness.frame(of: 2)
    _ = harness.manager.switchWorkspace(.next)
    #expect(harness.workspaces() == [1: 1])
    #expect(harness.frame(of: 2) == floatedFrame)
    #expect(harness.backend.unfocusCount == 0, "a floated window stays on screen, with focus")
  }
}
