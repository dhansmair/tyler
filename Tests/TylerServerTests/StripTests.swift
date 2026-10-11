import CoreGraphics
import Testing
import TylerCore

@testable import TylerServer

/// The strip layout on the primary display: three half windows, two in view at a time.
@Suite("Strip layout")
@MainActor
struct StripTests {
  /// Where the two windows in view go: the same halves as `tall` with two windows.
  private let halves = TallLayout().frames(count: 2, in: FakeDisplays.main.visibleFrame)

  /// Windows 1, 2 and 3 in the strip, window 1 focused.
  private func strip(displays: FakeDisplays = FakeDisplays()) async -> ManagerHarness {
    let harness = ManagerHarness([1, 2, 3], displays: displays)
    await harness.osFocus(1)
    _ = harness.manager.setLayout(.set(.strip))
    await harness.settle()
    harness.backend.clearRecordedCalls()
    return harness
  }

  @Test func theWindowsThatDoNotFitWaitParked() async {
    let harness = await strip()
    #expect(harness.frame(of: 1) == halves[0])
    #expect(harness.frame(of: 2) == halves[1])
    #expect(harness.isParked(3))
    #expect(harness.workspaces() == [1: 1, 2: 1, 3: 1], "a parked window stays on its workspace")
  }

  @Test func focusingAWindowOutOfViewScrollsToIt() async {
    let harness = await strip()
    _ = harness.manager.focus(.next)
    #expect(harness.isParked(3), "window 2 was in view already")
    #expect(harness.manager.focus(.next) == .ok)
    #expect(harness.isParked(1))
    #expect(harness.frame(of: 2) == halves[0])
    #expect(harness.frame(of: 3) == halves[1])
    #expect(harness.backend.focusCalls.last == WindowID(3))
  }

  @Test func clickingAWindowOutOfViewScrollsToIt() async {
    let harness = await strip()
    await harness.osFocus(3)
    #expect(harness.isParked(1))
    #expect(harness.frame(of: 3) == halves[1])
  }

  @Test func switchingWorkspacesLeavesWindowsOutOfViewParked() async {
    let harness = await strip()
    _ = harness.manager.switchWorkspace(.next)
    await harness.settle()
    _ = harness.manager.switchWorkspace(.prev)
    await harness.settle()
    #expect(!harness.backend.moves.contains { $0.id == WindowID(3) }, "it never moved")
    #expect(harness.isParked(3))
    #expect(harness.frame(of: 1) == halves[0])
  }

  @Test func aWindowOutOfViewStaysOnItsWorkspaceBesideAnotherDisplay() async {
    // Window 3 waits out of view at the laptop's left edge, away from the display to the right.
    let harness = await strip(
      displays: FakeDisplays(displays: [FakeDisplays.main, FakeDisplays.right]))
    _ = harness.manager.retile()
    #expect(harness.workspaces()[3] == 1)
    #expect(harness.isParked(3))
  }

  @Test func tilingOffBringsWindowsOutOfViewBack() async {
    let harness = await strip()
    _ = harness.manager.setTiling(.off)
    #expect(harness.frame(of: 3) == ManagerHarness.originalFrame(index: 2))
    #expect(harness.frame(of: 1) == halves[0], "windows in view stay")
  }

  @Test func aRestartKeepsTheView() async {
    let harness = await strip()
    await harness.osFocus(3)
    let successor = harness.successor(saved: harness.manager.handOver())
    #expect(successor.backend.moves.isEmpty, "every window is already where it belongs")
    _ = successor.manager.retile()
    #expect(successor.isParked(1))
    #expect(successor.frame(of: 3) == halves[1])
  }

  // MARK: - Sizes

  @Test func aFullWindowFillsTheViewAlone() async {
    let harness = await strip()
    #expect(harness.manager.setSize(.set(.full)) == .message("size full"))
    #expect(harness.frame(of: 1) == harness.area)
    #expect(harness.isParked(2))
    #expect(harness.isParked(3))
  }

  @Test func aQuarterStacksWithTheNextWindow() async {
    let harness = await strip()
    #expect(harness.manager.setSize(.set(.quarter)) == .message("size quarter"))
    let top = harness.frame(of: 1)
    #expect(top?.minX == harness.frame(of: 2)?.minX)
    #expect(top?.maxY == harness.frame(of: 2)?.minY, "window 2 goes below window 1")
    #expect(harness.frame(of: 3) == halves[1], "window 3 comes into view beside them")
  }

  @Test func aQuarterWithoutANeighbourIsAnError() async {
    let harness = ManagerHarness([1])
    await harness.osFocus(1)
    _ = harness.manager.setLayout(.set(.strip))
    #expect(
      harness.manager.setSize(.set(.quarter))
        == .error(
          "a quarter window shares its column with the next or previous window, and neither is free"
        ))
  }

  @Test func nextCyclesTheSize() async {
    let harness = await strip()
    #expect(harness.manager.setSize(.next) == .message("size full"))
    #expect(harness.manager.setSize(.next) == .message("size quarter"))
    #expect(harness.manager.setSize(.next) == .message("size half"))
  }

  @Test func otherLayoutsKeepTheSizeForTheStrip() async {
    let harness = ManagerHarness([1, 2])
    await harness.osFocus(1)
    #expect(
      harness.manager.setSize(.set(.full)) == .message("size full (used by the strip layout)"))
    #expect(harness.frame(of: 1) == halves[0], "tall ignores it")
    _ = harness.manager.setLayout(.set(.strip))
    #expect(harness.frame(of: 1) == harness.area)
  }

  @Test func sizeNeedsAFocusedTiledWindow() {
    let harness = ManagerHarness([1, 2])
    #expect(harness.manager.setSize(.set(.full)) == .error("the focused window is not tiled"))
  }

  // MARK: - Scrolling

  /// Three frames of 16 ms: two steps, then the final placement.
  private static func animated(_ clock: TestClock) async -> ManagerHarness {
    let harness = ManagerHarness(
      [1, 2, 3],
      animator: Animator(
        duration: .milliseconds(48), frameInterval: .milliseconds(16), clock: clock))
    await harness.osFocus(2)
    _ = harness.manager.setLayout(.set(.strip))
    await harness.settle()
    harness.backend.clearRecordedCalls()
    return harness
  }

  private func runAnimations(_ harness: ManagerHarness, _ clock: TestClock) async {
    await harness.settle()
    while clock.hasSleepers {
      clock.advance(by: .milliseconds(16))
      await harness.settle()
    }
  }

  @Test func focusingAWindowOutOfViewSlidesTheStrip() async throws {
    let clock = TestClock()
    let harness = await Self.animated(clock)
    let parked = try #require(harness.frame(of: 3))
    _ = harness.manager.focus(.next)
    #expect(harness.frame(of: 3)?.origin == parked.origin, "it starts where it is parked")
    await runAnimations(harness, clock)
    let steps = harness.backend.nudges.filter { $0.id == WindowID(3) }.map(\.origin.x)
    #expect(steps.count == 2)
    #expect(steps == steps.sorted(by: >), "it comes in from the right")
    #expect(harness.everyPositionIsAllowed())
    #expect(harness.isParked(1))
    #expect(harness.frame(of: 2) == halves[0])
    #expect(harness.frame(of: 3) == halves[1])
  }

  @Test func theFocusEventOfAScrollLetsItRunOn() async {
    let clock = TestClock()
    let harness = await Self.animated(clock)
    _ = harness.manager.focus(.next)
    await harness.osFocus(3)
    #expect(harness.manager.animation != nil, "still sliding")
    await runAnimations(harness, clock)
    #expect(harness.frame(of: 3) == halves[1])
  }

  @Test func clickingAWindowOutOfViewSlidesTheStrip() async {
    let clock = TestClock()
    let harness = await Self.animated(clock)
    await harness.osFocus(3)
    await runAnimations(harness, clock)
    #expect(harness.backend.nudges.contains { $0.id == WindowID(3) })
    #expect(harness.frame(of: 3) == halves[1])
  }
}
