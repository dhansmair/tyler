import CoreGraphics
import MWMCore
import Testing

@testable import MWMServer

// MARK: - Moving windows between monitors

@Suite("Monitors: move-to-monitor")
@MainActor
struct MoveToMonitorTests {
  @Test func withoutFollowTheWindowParksAndFocusStays() async {
    let harness = MonitorHarness([1, 2])
    await harness.osFocus(2)
    #expect(harness.manager.moveToMonitor(.down, follow: false) == .message("moved to monitor 2"))
    #expect(harness.isParked(2))
    #expect(harness.frame(of: 1) == harness.area)
    #expect(harness.monitors() == [1: 1, 2: 2])
    #expect(harness.backend.focusCalls == [WindowID(1)])
  }

  @Test func withFollowTheViewGoesAlong() async {
    let harness = MonitorHarness([1, 2])
    await harness.osFocus(2)
    #expect(
      harness.manager.moveToMonitor(.number(3), follow: true) == .message("moved to monitor 3"))
    #expect(harness.frame(of: 2) == harness.area)
    #expect(harness.isParked(1))
    #expect(harness.manager.monitors.currentIndex == 2)
    #expect(harness.backend.focusCalls == [WindowID(2)])
  }

  @Test func theMovedWindowIsFocusedWhenYouGetThere() async {
    let harness = MonitorHarness([1, 2, 3])
    await harness.osFocus(3)
    _ = harness.manager.moveToMonitor(.down, follow: false)
    await harness.osFocus(1)
    _ = harness.manager.moveToMonitor(.down, follow: false)
    harness.backend.clearRecordedCalls()
    _ = harness.manager.switchMonitor(.down)
    #expect(harness.backend.focusCalls == [WindowID(1)])
  }

  @Test func movingTheLastWindowLeavesAnEmptyMonitorWithoutFocusCalls() async {
    let harness = MonitorHarness([1])
    await harness.osFocus(1)
    _ = harness.manager.moveToMonitor(.up, follow: false)
    #expect(harness.monitors() == [1: 4])
    #expect(harness.isParked(1))
    #expect(harness.backend.focusCalls.isEmpty)
  }

  @Test func movingToTheSameMonitorDoesNothing() async {
    let harness = MonitorHarness([1, 2])
    await harness.osFocus(1)
    #expect(
      harness.manager.moveToMonitor(.number(1), follow: false) == .message("already on monitor 1"))
    #expect(harness.backend.moves.isEmpty)
  }

  @Test func onlyATiledFocusedWindowCanMove() async {
    let harness = MonitorHarness([1], extra: [makeWindow(id: 7, kind: .dialog)])
    #expect(
      harness.manager.moveToMonitor(.down, follow: false)
        == .error("the focused window is not tiled"))
    await harness.osFocus(7)
    #expect(
      harness.manager.moveToMonitor(.down, follow: false)
        == .error("the focused window is not tiled"))
  }

  @Test func aTargetOutOfRangeIsAnError() async {
    let harness = MonitorHarness([1])
    await harness.osFocus(1)
    #expect(
      harness.manager.moveToMonitor(.number(9), follow: true)
        == .error("monitor 9 does not exist (use 1 to 4)"))
  }

  // MARK: Focus-driven switching

  @Test func focusingAParkedWindowSwitchesToItsMonitor() async {
    let harness = MonitorHarness([1, 2])
    await harness.osFocus(2)
    _ = harness.manager.moveToMonitor(.number(3), follow: false)
    await harness.osFocus(1)  // the echo of mwmd focusing window 1
    harness.backend.clearRecordedCalls()

    await harness.osFocus(2)  // the user cmd-tabs to the parked window
    #expect(harness.manager.monitors.currentIndex == 2)
    #expect(harness.frame(of: 2) == harness.area)
    #expect(harness.isParked(1))
    #expect(harness.backend.focusCalls.isEmpty, "the OS already focused it")
  }

  @Test func theEchoOfMwmdsOwnFocusDoesNotSwitchBack() async {
    let harness = MonitorHarness([1, 2])
    await harness.osFocus(2)
    _ = harness.manager.moveToMonitor(.down, follow: false)
    await harness.osFocus(1)
    _ = harness.manager.switchMonitor(.down)  // mwmd focuses window 2
    _ = harness.manager.switchMonitor(.up)  // and quickly back
    // Window 2's focus event arrives late, while it is parked again.
    await harness.osFocus(2)
    #expect(harness.manager.monitors.currentIndex == 0)
  }

  @Test func focusingAParkedWindowWithTilingOffDoesNotSwitch() async {
    let harness = MonitorHarness([1, 2])
    await harness.osFocus(2)
    _ = harness.manager.moveToMonitor(.down, follow: false)
    await harness.osFocus(1)
    _ = harness.manager.setTiling(.off)
    await harness.osFocus(2)
    #expect(harness.manager.monitors.currentIndex == 0)
  }
}
