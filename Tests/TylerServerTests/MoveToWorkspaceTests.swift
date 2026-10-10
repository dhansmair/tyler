import CoreGraphics
import Testing
import TylerCore

@testable import TylerServer

// MARK: - Moving windows between workspaces

@Suite("Workspaces: move-to-workspace")
@MainActor
struct MoveToWorkspaceTests {
  @Test func withoutFollowTheWindowParksAndFocusStays() async {
    let harness = WorkspaceHarness([1, 2])
    await harness.osFocus(2)
    #expect(
      harness.manager.moveToWorkspace(.down, follow: false) == .message("moved to workspace 2"))
    #expect(harness.isParked(2))
    #expect(harness.frame(of: 1) == harness.area)
    #expect(harness.workspaces() == [1: 1, 2: 2])
    #expect(harness.backend.focusCalls == [WindowID(1)])
  }

  @Test func withFollowTheViewGoesAlong() async {
    let harness = WorkspaceHarness([1, 2])
    await harness.osFocus(2)
    #expect(
      harness.manager.moveToWorkspace(.number(3), follow: true) == .message("moved to workspace 3"))
    #expect(harness.frame(of: 2) == harness.area)
    #expect(harness.isParked(1))
    #expect(harness.manager.workspaces.currentIndex == 2)
    #expect(harness.backend.focusCalls == [WindowID(2)])
  }

  @Test func theMovedWindowIsFocusedWhenYouGetThere() async {
    let harness = WorkspaceHarness([1, 2, 3])
    await harness.osFocus(3)
    _ = harness.manager.moveToWorkspace(.down, follow: false)
    await harness.osFocus(1)
    _ = harness.manager.moveToWorkspace(.down, follow: false)
    harness.backend.clearRecordedCalls()
    _ = harness.manager.switchWorkspace(.down)
    #expect(harness.backend.focusCalls == [WindowID(1)])
  }

  @Test func movingTheLastWindowTakesFocusFromItOnceParked() async {
    let harness = WorkspaceHarness([1])
    await harness.osFocus(1)
    _ = harness.manager.moveToWorkspace(.up, follow: false)
    #expect(harness.workspaces() == [1: 4])
    #expect(harness.isParked(1))
    #expect(harness.backend.focusCalls.isEmpty)
    #expect(harness.backend.unfocusCount == 1)
  }

  @Test func movingToTheSameWorkspaceDoesNothing() async {
    let harness = WorkspaceHarness([1, 2])
    await harness.osFocus(1)
    #expect(
      harness.manager.moveToWorkspace(.number(1), follow: false)
        == .message("already on workspace 1"))
    #expect(harness.backend.moves.isEmpty)
  }

  @Test func onlyATiledFocusedWindowCanMove() async {
    let harness = WorkspaceHarness([1], extra: [makeWindow(id: 7, kind: .dialog)])
    #expect(
      harness.manager.moveToWorkspace(.down, follow: false)
        == .error("the focused window is not tiled"))
    await harness.osFocus(7)
    #expect(
      harness.manager.moveToWorkspace(.down, follow: false)
        == .error("the focused window is not tiled"))
  }

  @Test func aTargetOutOfRangeIsAnError() async {
    let harness = WorkspaceHarness([1])
    await harness.osFocus(1)
    #expect(
      harness.manager.moveToWorkspace(.number(9), follow: true)
        == .error("workspace 9 does not exist (use 1 to 4)"))
  }

  // MARK: Focus-driven switching

  @Test func focusingAParkedWindowSwitchesToItsWorkspace() async {
    let harness = WorkspaceHarness([1, 2])
    await harness.osFocus(2)
    _ = harness.manager.moveToWorkspace(.number(3), follow: false)
    await harness.osFocus(1)  // the echo of tylerd focusing window 1
    harness.backend.clearRecordedCalls()

    await harness.osFocus(2)  // the user cmd-tabs to the parked window
    #expect(harness.manager.workspaces.currentIndex == 2)
    #expect(harness.frame(of: 2) == harness.area)
    #expect(harness.isParked(1))
    #expect(harness.backend.focusCalls.isEmpty, "the OS already focused it")
  }

  @Test func theEchoOfTylerdsOwnFocusDoesNotSwitchBack() async {
    let harness = WorkspaceHarness([1, 2])
    await harness.osFocus(2)
    _ = harness.manager.moveToWorkspace(.down, follow: false)
    await harness.osFocus(1)
    _ = harness.manager.switchWorkspace(.down)  // tylerd focuses window 2
    _ = harness.manager.switchWorkspace(.up)  // and quickly back
    // Window 2's focus event arrives late, while it is parked again.
    await harness.osFocus(2)
    #expect(harness.manager.workspaces.currentIndex == 0)
  }

  @Test func focusingAParkedWindowWithTilingOffDoesNotSwitch() async {
    let harness = WorkspaceHarness([1, 2])
    await harness.osFocus(2)
    _ = harness.manager.moveToWorkspace(.down, follow: false)
    await harness.osFocus(1)
    _ = harness.manager.setTiling(.off)
    await harness.osFocus(2)
    #expect(harness.manager.workspaces.currentIndex == 0)
  }
}
