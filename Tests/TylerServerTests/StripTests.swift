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
    // Parked at the right edge, window 3 lies almost wholly on the display to the right.
    let harness = await strip(
      displays: FakeDisplays(displays: [FakeDisplays.main, FakeDisplays.secondary]))
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

  @Test func twoQuartersShareAColumn() async {
    let harness = await strip()
    _ = harness.manager.setSize(.set(.quarter))
    await harness.osFocus(2)
    _ = harness.manager.setSize(.set(.quarter))
    let column = harness.frame(of: 1)
    #expect(column?.minX == harness.frame(of: 2)?.minX)
    #expect(column?.maxY == harness.frame(of: 2)?.minY)
    #expect(harness.frame(of: 3) == halves[1], "window 3 comes into view beside them")
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
}
