import CoreGraphics
import Testing
import TylerCore
import TylerTestSupport

@testable import TylerServer

// MARK: - Switching

@Suite("Workspaces: switching")
@MainActor
struct WorkspaceSwitchScenarios {
  @Test func existingWindowsStartOnTheFirstWorkspace() {
    let harness = ManagerHarness([1, 2])
    #expect(harness.workspaces() == [1: 1, 2: 1])
  }

  @Test func switchingParksTheCurrentWindowsAndGivesNoFocusToAnEmptyWorkspace() {
    let harness = ManagerHarness([1, 2])
    #expect(harness.manager.switchWorkspace(.next) == .message("workspace 2"))
    #expect(harness.isParked(1))
    #expect(harness.isParked(2))
    #expect(harness.workspaces() == [1: 1, 2: 1], "parked windows keep their workspace")
    #expect(harness.backend.focusCalls.isEmpty)
    #expect(harness.backend.unfocusCount == 0, "no window had focus")
  }

  @Test func switchingToAnEmptyWorkspaceTakesFocusFromTheParkedWindow() async {
    let harness = ManagerHarness([1, 2])
    await harness.osFocus(2)
    _ = harness.manager.switchWorkspace(.next)
    #expect(harness.isParked(2))
    #expect(harness.backend.focusCalls.isEmpty)
    #expect(harness.backend.unfocusCount == 1)
  }

  @Test func failingToTakeFocusStillSwitchesAndSaysSo() async {
    let harness = ManagerHarness([1])
    await harness.osFocus(1)
    harness.backend.isUnfocusFailing = true
    #expect(
      harness.manager.switchWorkspace(.next)
        == .message("workspace 2; cannot take focus from window 1: fake refusal"))
    #expect(harness.isParked(1))
    #expect(harness.backend.unfocusCount == 1)
  }

  @Test func aWindowThatRefusesFocusIsReportedAfterTheSwitch() async {
    let harness = ManagerHarness([1, 2])
    await harness.osFocus(2)
    _ = harness.manager.moveToWorkspace(.next, follow: false)
    harness.backend.failingFocus = [WindowID(2)]
    #expect(
      harness.manager.switchWorkspace(.next)
        == .message("workspace 2; cannot focus window 2: fake refusal"))
    #expect(harness.manager.workspaces.currentIndex == 1)
  }

  @Test func newWindowsOpenOnTheCurrentWorkspace() async {
    let harness = ManagerHarness([1, 2])
    _ = harness.manager.switchWorkspace(.number(3))
    harness.backend.windows.append(makeWindow(id: 9))
    harness.backend.send(.created(makeWindow(id: 9)))
    await harness.settle()
    #expect(harness.workspaces() == [1: 1, 2: 1, 9: 3])
    #expect(harness.frame(of: 9) == harness.area)
  }

  @Test func switchingBackRestoresTheSlotsAndFocusesTheFocusedWindow() async {
    let harness = ManagerHarness([1, 2])
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
    let harness = ManagerHarness([1])
    _ = harness.manager.switchWorkspace(.number(from))
    #expect(harness.manager.switchWorkspace(target) == .message(expected))
  }

  @Test(arguments: [5, 0])
  func aWorkspaceOutOfRangeIsAnError(number: Int) {
    let harness = ManagerHarness([1])
    #expect(
      harness.manager.switchWorkspace(.number(number))
        == .error("workspace \(number) does not exist (use 1 to 4)"))
    #expect(harness.backend.moves.isEmpty)
  }

  @Test(arguments: [([1, 2, 3, 4], "1 to 4"), ([5, 6, 9], "5, 6, 9"), ([7], "7")])
  func theErrorNamesTheWorkspacesThereAre(numbers: [Int], named: String) {
    #expect(WorkspaceController.describe(numbers) == named)
  }

  @Test func switchingToTheCurrentWorkspaceMovesNothing() {
    let harness = ManagerHarness([1, 2])
    #expect(harness.manager.switchWorkspace(.number(1)) == .message("workspace 1"))
    #expect(harness.backend.moves.isEmpty)
  }

  @Test func switchingNeedsTilingAndPermission() {
    let harness = ManagerHarness([1])
    _ = harness.manager.setTiling(.off)
    #expect(harness.manager.switchWorkspace(.next) == .error(WindowManager.tilingOffMessage))
    #expect(
      harness.manager.moveToWorkspace(.next, follow: false)
        == .error(WindowManager.tilingOffMessage))

    let waiting = WindowManager(
      backend: FakeWindowSystem(), displays: FakeDisplays(), gate: FakeGate(isTrusted: false))
    #expect(waiting.switchWorkspace(.next) == .error(WindowManager.permissionMessage))
  }

  @Test func handleRoutesTheWorkspaceRequests() async {
    let harness = ManagerHarness([1, 2])
    await harness.osFocus(2)
    #expect(
      harness.manager.handle(.moveToWorkspace(.number(3), follow: false))
        == .message("moved to workspace 3"))
    #expect(harness.manager.handle(.workspace(.number(3))) == .message("workspace 3"))
    #expect(harness.workspaces() == [1: 1, 2: 3])
  }

  @Test func tilingOffBringsParkedWindowsBackAndForgetsTheirWorkspace() {
    let harness = ManagerHarness([1, 2, 3])
    _ = harness.manager.switchWorkspace(.next)
    harness.backend.windows.append(makeWindow(id: 9))
    _ = harness.manager.setTiling(.off)
    #expect(harness.frame(of: 1) == ManagerHarness.originalFrame(index: 0))
    #expect(harness.frame(of: 3) == ManagerHarness.originalFrame(index: 2))
    #expect(harness.workspaces().isEmpty)
  }

  @Test func turningTilingBackOnTilesEverythingOntoTheCurrentWorkspace() {
    let harness = ManagerHarness([1, 2])
    _ = harness.manager.switchWorkspace(.next)
    _ = harness.manager.setTiling(.off)
    _ = harness.manager.setTiling(.on)
    #expect(harness.workspaces() == [1: 2, 2: 2])
  }

  @Test func aParkedWindowThatClosesLeavesItsWorkspace() async {
    let harness = ManagerHarness([1, 2])
    _ = harness.manager.switchWorkspace(.next)
    harness.backend.send(.destroyed(WindowID(1)))
    await harness.settle()
    #expect(harness.workspaces() == [2: 1])
  }

  @Test func aParkedWindowStaysOnItsWorkspaceWhateverItsFrameSays() async {
    let displays = FakeDisplays(displays: [FakeDisplays.main, FakeDisplays.right])
    let harness = ManagerHarness([1, 2], displays: displays)
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
    let harness = ManagerHarness(
      [1, 2], displays: FakeDisplays(displays: [FakeDisplays.main, tall]))
    let slots = [harness.frame(of: 1), harness.frame(of: 2)]
    _ = harness.manager.switchWorkspace(.next)
    await harness.settle()  // the manager learns the parked frames
    _ = harness.manager.switchWorkspace(.prev)
    #expect(harness.workspaces() == [1: 1, 2: 1])
    #expect([harness.frame(of: 1), harness.frame(of: 2)] == slots)
  }

  @Test func aParkedWindowThatIsMinimizedComesBackOnTheCurrentWorkspace() async {
    let harness = ManagerHarness([1, 2])
    _ = harness.manager.switchWorkspace(.next)
    harness.backend.send(.updated(makeWindow(id: 1, isMinimized: true)))
    await harness.settle()
    #expect(harness.workspaces() == [2: 1])
    harness.backend.send(.updated(makeWindow(id: 1)))
    await harness.settle()
    #expect(harness.workspaces() == [1: 2, 2: 1])
  }

  @Test func floatedWindowsBelongToNoWorkspaceAndAreNeverParked() async {
    let harness = ManagerHarness([1, 2])
    await harness.osFocus(2)
    _ = harness.manager.setFloat(.toggle)
    let floatedFrame = harness.frame(of: 2)
    _ = harness.manager.switchWorkspace(.next)
    #expect(harness.workspaces() == [1: 1])
    #expect(harness.frame(of: 2) == floatedFrame)
    #expect(harness.backend.unfocusCount == 0, "a floated window stays on screen, with focus")
  }
}
