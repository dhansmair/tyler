import CoreGraphics
import MWMCore
import Testing

@testable import MWMServer

/// Shared setup for the monitor, move-to-monitor and restore suites.
@MainActor
struct MonitorHarness {
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
    animator: Animator = .snap
  ) {
    backend = FakeBackend(windows: Self.spread(ids) + extra)
    manager = WindowManager(
      backend: backend, displays: displays, gate: FakeGate(isTrusted: true), animator: animator)
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

  func parked(_ windowID: UInt32) -> CGRect? {
    frame(of: windowID).map { Parking.frame(for: $0.size, on: display) }
  }

  func isParked(_ windowID: UInt32) -> Bool {
    guard let frame = frame(of: windowID) else { return false }
    return frame.origin == Parking.frame(for: frame.size, on: display).origin
  }

  /// Window id → 1-based monitor, for windows on a monitor.
  func monitors() -> [UInt32: Int] {
    guard case .windows(let windows) = manager.windows() else { return [:] }
    return Dictionary(
      uniqueKeysWithValues: windows.compactMap { window in
        window.monitor.map { (window.id.rawValue, $0) }
      })
  }

  /// Focuses `windowID` the way the OS would, and waits for the manager to see it.
  func osFocus(_ windowID: UInt32) async {
    backend.send(.focused(WindowID(windowID)))
    await settle()
  }
}

// MARK: - Switching

@Suite("Monitors: switching")
@MainActor
struct MonitorSwitchTests {
  @Test func existingWindowsStartOnTheFirstMonitor() {
    let harness = MonitorHarness([1, 2])
    #expect(harness.monitors() == [1: 1, 2: 1])
  }

  @Test func switchingParksTheCurrentWindowsAndGivesNoFocusToAnEmptyMonitor() {
    let harness = MonitorHarness([1, 2])
    #expect(harness.manager.switchMonitor(.down) == .message("monitor 2"))
    #expect(harness.isParked(1))
    #expect(harness.isParked(2))
    #expect(harness.monitors() == [1: 1, 2: 1], "parked windows keep their monitor")
    #expect(harness.backend.focusCalls.isEmpty)
  }

  @Test func newWindowsOpenOnTheCurrentMonitor() async {
    let harness = MonitorHarness([1, 2])
    _ = harness.manager.switchMonitor(.number(3))
    harness.backend.windows.append(makeWindow(id: 9))
    harness.backend.send(.created(makeWindow(id: 9)))
    await harness.settle()
    #expect(harness.monitors() == [1: 1, 2: 1, 9: 3])
    #expect(harness.frame(of: 9) == harness.area)
  }

  @Test func switchingBackRestoresTheSlotsAndFocusesTheFocusedWindow() async {
    let harness = MonitorHarness([1, 2])
    let slots = [harness.frame(of: 1), harness.frame(of: 2)]
    await harness.osFocus(2)
    _ = harness.manager.switchMonitor(.down)
    _ = harness.manager.switchMonitor(.up)
    #expect([harness.frame(of: 1), harness.frame(of: 2)] == slots)
    #expect(harness.backend.focusCalls == [WindowID(2)])
  }

  @Test(arguments: [
    (MonitorTarget.down, 4, "monitor 1"), (.up, 1, "monitor 4"), (.number(2), 1, "monitor 2"),
  ])
  func upAndDownWrapAtTheEnds(target: MonitorTarget, from: Int, expected: String) {
    let harness = MonitorHarness([1])
    _ = harness.manager.switchMonitor(.number(from))
    #expect(harness.manager.switchMonitor(target) == .message(expected))
  }

  @Test(arguments: [5, 0])
  func aMonitorOutOfRangeIsAnError(number: Int) {
    let harness = MonitorHarness([1])
    #expect(
      harness.manager.switchMonitor(.number(number))
        == .error("monitor \(number) does not exist (use 1 to 4)"))
    #expect(harness.backend.moves.isEmpty)
  }

  @Test func switchingToTheCurrentMonitorMovesNothing() {
    let harness = MonitorHarness([1, 2])
    #expect(harness.manager.switchMonitor(.number(1)) == .message("monitor 1"))
    #expect(harness.backend.moves.isEmpty)
  }

  @Test func switchingNeedsTilingAndPermission() {
    let harness = MonitorHarness([1])
    _ = harness.manager.setTiling(.off)
    #expect(harness.manager.switchMonitor(.down) == .error(WindowManager.tilingOffMessage))
    #expect(
      harness.manager.moveToMonitor(.down, follow: false)
        == .error(WindowManager.tilingOffMessage))

    let waiting = WindowManager(
      backend: FakeBackend(), displays: FakeDisplays(), gate: FakeGate(isTrusted: false))
    #expect(waiting.switchMonitor(.down) == .error(WindowManager.permissionMessage))
  }

  @Test func handleRoutesTheMonitorRequests() async {
    let harness = MonitorHarness([1, 2])
    await harness.osFocus(2)
    #expect(
      harness.manager.handle(.moveToMonitor(.number(3), follow: false))
        == .message("moved to monitor 3"))
    #expect(harness.manager.handle(.monitor(.number(3))) == .message("monitor 3"))
    #expect(harness.monitors() == [1: 1, 2: 3])
  }

  @Test func tilingOffBringsParkedWindowsBackAndForgetsTheirMonitor() {
    let harness = MonitorHarness([1, 2, 3])
    _ = harness.manager.switchMonitor(.down)
    harness.backend.windows.append(makeWindow(id: 9))
    _ = harness.manager.setTiling(.off)
    #expect(harness.frame(of: 1) == MonitorHarness.originalFrame(index: 0))
    #expect(harness.frame(of: 3) == MonitorHarness.originalFrame(index: 2))
    #expect(harness.monitors().isEmpty)
  }

  @Test func turningTilingBackOnTilesEverythingOntoTheCurrentMonitor() {
    let harness = MonitorHarness([1, 2])
    _ = harness.manager.switchMonitor(.down)
    _ = harness.manager.setTiling(.off)
    _ = harness.manager.setTiling(.on)
    #expect(harness.monitors() == [1: 2, 2: 2])
  }

  @Test func aParkedWindowThatClosesLeavesItsMonitor() async {
    let harness = MonitorHarness([1, 2])
    _ = harness.manager.switchMonitor(.down)
    harness.backend.send(.destroyed(WindowID(1)))
    await harness.settle()
    #expect(harness.monitors() == [2: 1])
  }

  @Test func aParkedWindowStaysOnItsMonitorWhateverItsFrameSays() async {
    let displays = FakeDisplays(displays: [FakeDisplays.main, FakeDisplays.secondary])
    let harness = MonitorHarness([1, 2], displays: displays)
    _ = harness.manager.switchMonitor(.down)
    // macOS (or the user) moves a parked window onto the other display.
    harness.backend.send(
      .updated(makeWindow(id: 1, frame: CGRect(x: 2000, y: 100, width: 300, height: 200))))
    await harness.settle()
    #expect(harness.monitors() == [1: 1, 2: 1])
  }

  @Test func parkedWindowsOverlappingAnotherDisplayComeBackWithTheirMonitor() async {
    // A tall display to the right: a window parked in the primary's corner overlaps it more
    // than the primary, so by frame alone it would count as being on that display.
    let tall = DisplayInfo(
      id: 3,
      frame: CGRect(x: 1800, y: 0, width: 1920, height: 2400),
      visibleFrame: CGRect(x: 1800, y: 0, width: 1920, height: 2400))
    let harness = MonitorHarness(
      [1, 2], displays: FakeDisplays(displays: [FakeDisplays.main, tall]))
    let slots = [harness.frame(of: 1), harness.frame(of: 2)]
    _ = harness.manager.switchMonitor(.down)
    await harness.settle()  // the manager learns the parked frames
    _ = harness.manager.switchMonitor(.up)
    #expect(harness.monitors() == [1: 1, 2: 1])
    #expect([harness.frame(of: 1), harness.frame(of: 2)] == slots)
  }

  @Test func aParkedWindowThatIsMinimizedComesBackOnTheCurrentMonitor() async {
    let harness = MonitorHarness([1, 2])
    _ = harness.manager.switchMonitor(.down)
    harness.backend.send(.updated(makeWindow(id: 1, isMinimized: true)))
    await harness.settle()
    #expect(harness.monitors() == [2: 1])
    harness.backend.send(.updated(makeWindow(id: 1)))
    await harness.settle()
    #expect(harness.monitors() == [1: 2, 2: 1])
  }

  @Test func floatedWindowsBelongToNoMonitorAndAreNeverParked() async {
    let harness = MonitorHarness([1, 2])
    await harness.osFocus(2)
    _ = harness.manager.toggleFloat()
    let floatedFrame = harness.frame(of: 2)
    _ = harness.manager.switchMonitor(.down)
    #expect(harness.monitors() == [1: 1])
    #expect(harness.frame(of: 2) == floatedFrame)
  }
}

// MARK: - Animation

@Suite("Monitors: animation")
@MainActor
struct MonitorAnimationTests {
  /// Three frames of 16 ms: two intermediate steps, then the final placement.
  private let clock = TestClock()
  private var animator: Animator {
    Animator(duration: .milliseconds(48), frameInterval: .milliseconds(16), clock: clock)
  }

  /// Advances the clock until no animation is waiting on it.
  private func runAnimations(_ harness: MonitorHarness) async {
    await harness.settle()
    while clock.hasSleepers {
      clock.advance(by: .milliseconds(16))
      await harness.settle()
    }
  }

  @Test func theStepCountFollowsTheDurationAndZeroSnaps() {
    #expect(Animator().stepCount == 13)
    #expect(animator.stepCount == 3)
    #expect(Animator.snap.stepCount == 0)
  }

  @Test func outgoingWindowsSlideUpThenPark() async {
    let harness = MonitorHarness([1, 2], animator: animator)
    let start = harness.frame(of: 1)
    _ = harness.manager.switchMonitor(.down)
    #expect(harness.frame(of: 1) == start, "nothing moves before the first frame")

    await runAnimations(harness)
    let steps = harness.backend.nudges.filter { $0.id == WindowID(1) }.map(\.origin)
    #expect(steps.count == 2)
    #expect(steps.allSatisfy { $0.y < (start?.minY ?? 0) }, "scrolling down moves windows up")
    #expect(harness.isParked(1))
    #expect(harness.isParked(2))
  }

  @Test func incomingWindowsStartADisplayHeightBelowAndEndInTheirSlots() async {
    let harness = MonitorHarness([1, 2], animator: animator)
    await harness.osFocus(2)
    _ = harness.manager.moveToMonitor(.down, follow: false)
    await runAnimations(harness)
    harness.backend.clearRecordedCalls()

    _ = harness.manager.switchMonitor(.down)
    let first = harness.backend.moves.first { $0.id == WindowID(2) }
    let height = harness.display.frame.height
    #expect(first?.frame == harness.area.offsetBy(dx: 0, dy: height))
    await runAnimations(harness)
    #expect(harness.frame(of: 2) == harness.area)
  }

  @Test func scrollingUpMovesTheOtherWay() async {
    let harness = MonitorHarness([1], animator: animator)
    let start = harness.frame(of: 1)
    _ = harness.manager.switchMonitor(.up)
    await runAnimations(harness)
    let steps = harness.backend.nudges.map(\.origin)
    #expect(!steps.isEmpty)
    #expect(steps.allSatisfy { $0.y > (start?.minY ?? 0) })
  }

  @Test func aCommandMidSlideJumpsToTheEndFirst() async {
    let harness = MonitorHarness([1, 2], animator: animator)
    _ = harness.manager.switchMonitor(.down)
    clock.advance(by: .milliseconds(16))
    await harness.settle()
    #expect(!harness.isParked(1), "mid-slide")

    // `list` doesn't interrupt; `retile` does, which parks the outgoing windows at once.
    _ = harness.manager.windows()
    #expect(!harness.isParked(1))
    _ = harness.manager.retile()
    #expect(harness.isParked(1))
    #expect(harness.isParked(2))

    // The cancelled slide must not move anything afterwards.
    let nudges = harness.backend.nudges.count
    await runAnimations(harness)
    #expect(harness.backend.nudges.count == nudges)
    #expect(harness.isParked(1))
  }

  @Test func switchingAgainMidSlideEndsWithTheSecondTargetVisible() async {
    let harness = MonitorHarness([1, 2], animator: animator)
    let slots = [harness.frame(of: 1), harness.frame(of: 2)]
    _ = harness.manager.switchMonitor(.down)
    _ = harness.manager.switchMonitor(.up)
    await runAnimations(harness)
    #expect([harness.frame(of: 1), harness.frame(of: 2)] == slots)
  }

  @Test func aNewWindowMidSlideFinishesTheSlideAndTiles() async {
    let harness = MonitorHarness([1], animator: animator)
    _ = harness.manager.switchMonitor(.down)
    harness.backend.windows.append(makeWindow(id: 9))
    harness.backend.send(.created(makeWindow(id: 9)))
    await harness.settle()
    #expect(harness.isParked(1))
    #expect(harness.frame(of: 9) == harness.area)
    #expect(harness.monitors() == [1: 1, 9: 2])
  }

  @Test func aWindowFailingMidSlideDoesNotStopTheOthers() async {
    let harness = MonitorHarness([1, 2], animator: animator)
    harness.backend.failingMoves = [WindowID(1)]
    _ = harness.manager.switchMonitor(.down)
    await runAnimations(harness)
    #expect(harness.isParked(2))
  }
}
