import CoreGraphics
import Testing
import TylerCore
import TylerTestSupport

@testable import TylerPlatform

/// Window 1 starts at (100, 50, 400, 300).
@Suite("MacWindowSystem: moving windows")
@MainActor
struct MacWindowSystemMovingTests {
  private let harness = WindowSystemHarness()

  private func started() async -> WindowSystemHarness {
    harness.addApp(100, windows: [1])
    await harness.start()
    _ = await harness.takeEvents()
    return harness
  }

  @Test func aWindowOfTheRightSizeIsOnlyMoved() async throws {
    let harness = await started()
    try harness.windowSystem.setFrame(
      CGRect(x: 600, y: 50, width: 400, height: 300), of: WindowID(1))
    #expect(harness.accessibility.calls(on: 1) == [.position(CGPoint(x: 600, y: 50))])
  }

  @Test func aResizeSetsTheSizeThePositionAndTheSizeAgain() async throws {
    let harness = await started()
    try harness.windowSystem.setFrame(
      CGRect(x: 0, y: 0, width: 500, height: 400), of: WindowID(1))
    let size = CGSize(width: 500, height: 400)
    #expect(harness.accessibility.calls(on: 1) == [.size(size), .position(.zero), .size(size)])
  }

  @Test func aWindowReachingPastItsNewFrameIsMovedFirst() async throws {
    let harness = await started()
    try harness.windowSystem.setFrame(
      CGRect(x: 100, y: 50, width: 200, height: 300), of: WindowID(1))
    #expect(harness.accessibility.calls(on: 1).first == .position(CGPoint(x: -100, y: 50)))
  }

  @Test func aPositionThatDidNotLandIsWrittenAgain() async throws {
    let harness = await started()
    harness.accessibility.losePosition(of: 1)
    let frame = CGRect(x: 600, y: 90, width: 500, height: 400)
    try harness.windowSystem.setFrame(frame, of: WindowID(1))
    #expect(harness.windowSystem.snapshot().first?.frame == frame)
  }

  /// Seen going to a wider display: the sizes written from the old one stop at its right edge.
  @Test func aWindowCrossingDisplaysGetsTheSizeItAskedFor() async throws {
    let harness = await started()
    harness.accessibility.capWidth(of: 1, to: 700, writes: 2)
    let frame = CGRect(x: 2000, y: -1400, width: 2500, height: 1300)
    try harness.windowSystem.setFrame(frame, of: WindowID(1))
    #expect(harness.windowSystem.snapshot().first?.frame == frame)
  }

  @Test func aWindowStayingOnItsDisplayIsNotWrittenTwiceForItsSize() async throws {
    let harness = await started()
    harness.accessibility.capWidth(of: 1, to: 450, writes: 2)
    try harness.windowSystem.setFrame(
      CGRect(x: 100, y: 50, width: 500, height: 300), of: WindowID(1))
    #expect(harness.accessibility.calls(on: 1).count == 3)
  }

  @Test func aSizeTheAppChoseIsNotWrittenAgain() async throws {
    let harness = await started()
    harness.accessibility.clamp(1, toAtLeast: CGSize(width: 600, height: 400))
    try harness.windowSystem.setFrame(
      CGRect(x: 0, y: 0, width: 500, height: 400), of: WindowID(1))
    #expect(harness.accessibility.calls(on: 1).count == 3)
  }

  @Test func aClampedSizeIsReported() async throws {
    let harness = await started()
    harness.accessibility.clamp(1, toAtLeast: CGSize(width: 350, height: 300))
    try harness.windowSystem.setFrame(CGRect(x: 0, y: 0, width: 300, height: 300), of: WindowID(1))
    #expect(
      await harness.takeEvents().updated.map(\.frame)
        == [CGRect(x: 0, y: 0, width: 350, height: 300)])
  }

  @Test func aFrameThatFitsIsNotReported() async throws {
    let harness = await started()
    try harness.windowSystem.setFrame(CGRect(x: 0, y: 0, width: 300, height: 200), of: WindowID(1))
    #expect(
      await harness.takeEvents().updated.map(\.frame)
        == [CGRect(x: 0, y: 0, width: 300, height: 200)],
      "the frame read back, so the manager knows it")
  }

  @Test func stepsGoThroughTheQueueAndLandBeforeTheFinalFrame() async throws {
    let harness = await started()
    try harness.windowSystem.setPosition(CGPoint(x: 200, y: 50), of: WindowID(1))
    try harness.windowSystem.setFrame(
      CGRect(x: 300, y: 50, width: 400, height: 300), of: WindowID(1))
    let calls = harness.accessibility.calls(on: 1)
    #expect(calls.last == .position(CGPoint(x: 300, y: 50)))
    #expect(harness.accessibility.frame(of: 1)?.origin == CGPoint(x: 300, y: 50))
    let queued = harness.windowSystem.takeQueuedWrites()
    #expect(queued.written + queued.skipped == 1)
  }

  @Test func aGrowingStepMovesThenResizes() async throws {
    harness.addApp(100, windows: [1, 2])
    await harness.start()
    try harness.windowSystem.setFrameStep(
      CGRect(x: 0, y: 0, width: 500, height: 400), of: WindowID(1))
    // Settling window 2 waits for its app's queue, which writes window 1's step meanwhile.
    try harness.windowSystem.setFrame(WindowSystemHarness.frame(of: 2), of: WindowID(2))
    #expect(
      harness.accessibility.calls(on: 1) == [
        .position(.zero), .size(CGSize(width: 500, height: 400)),
      ])
    #expect(harness.windowSystem.takeQueuedWrites().written == 1)
  }

  @Test func aShrinkingStepResizesThenMoves() async throws {
    harness.addApp(100, windows: [1, 2])
    await harness.start()
    try harness.windowSystem.setFrameStep(
      CGRect(x: 0, y: 0, width: 300, height: 200), of: WindowID(1))
    try harness.windowSystem.setFrame(WindowSystemHarness.frame(of: 2), of: WindowID(2))
    #expect(
      harness.accessibility.calls(on: 1) == [
        .size(CGSize(width: 300, height: 200)), .position(.zero),
      ])
  }

  // MARK: - Steps held up by a busy app

  private func startedWithTwoApps() async -> WindowSystemHarness {
    harness.addApp(100, windows: [1, 2])
    harness.addApp(200, windows: [3, 4])
    await harness.start()
    _ = await harness.takeEvents()
    return harness
  }

  private func step(_ id: UInt32, toX originX: CGFloat) throws {
    try harness.windowSystem.setPosition(CGPoint(x: originX, y: 50), of: WindowID(id))
  }

  @Test func aFinalFrameWaitsForTheStepUnderWayAndDropsTheOneWaiting() async throws {
    let harness = await startedWithTwoApps()
    harness.accessibility.hold(1)
    try step(1, toX: 10)
    harness.accessibility.waitUntilHeld(1)
    try step(1, toX: 20)
    try step(2, toX: 30)
    harness.accessibility.open(1, after: .milliseconds(30))

    try harness.windowSystem.setFrame(
      CGRect(x: 40, y: 50, width: 400, height: 300), of: WindowID(1))
    #expect(
      harness.accessibility.calls(on: 1)
        == [.position(CGPoint(x: 10, y: 50)), .position(CGPoint(x: 40, y: 50))],
      "the step to 20 was dropped")
    #expect(harness.accessibility.calls(on: 2) == [.position(CGPoint(x: 30, y: 50))])
  }

  @Test func anAppDoesNotWaitForAnother() async throws {
    let harness = await startedWithTwoApps()
    harness.accessibility.hold(1)
    try step(1, toX: 10)
    harness.accessibility.waitUntilHeld(1)
    try step(3, toX: 30)
    try harness.windowSystem.setFrame(WindowSystemHarness.frame(of: 4), of: WindowID(4))
    #expect(harness.accessibility.calls(on: 3) == [.position(CGPoint(x: 30, y: 50))])
    #expect(harness.accessibility.calls(on: 1).isEmpty, "app 100 is still held")

    harness.accessibility.open(1)
    try harness.windowSystem.setFrame(WindowSystemHarness.frame(of: 2), of: WindowID(2))
    #expect(harness.accessibility.calls(on: 1) == [.position(CGPoint(x: 10, y: 50))])
  }

  @Test func theQueuedWritesAddUpEveryApp() async throws {
    let harness = await startedWithTwoApps()
    harness.accessibility.hold(1)
    try step(1, toX: 10)
    harness.accessibility.waitUntilHeld(1)
    try step(1, toX: 20)
    try step(1, toX: 25)
    try step(3, toX: 30)
    harness.accessibility.open(1)
    try harness.windowSystem.setFrame(WindowSystemHarness.frame(of: 2), of: WindowID(2))
    try harness.windowSystem.setFrame(WindowSystemHarness.frame(of: 4), of: WindowID(4))
    let queued = harness.windowSystem.takeQueuedWrites()
    #expect(queued.written == 3)
    #expect(queued.skipped == 1)
  }

  @Test(arguments: [
    (
      CGRect(x: 0, y: 0, width: 500, height: 400),
      [FakeAXClient.Call.position(.zero), .size(CGSize(width: 500, height: 400))]
    ),
    (
      CGRect(x: 0, y: 0, width: 300, height: 200),
      [FakeAXClient.Call.size(CGSize(width: 300, height: 200)), .position(.zero)]
    ),
  ])
  func inPassingAGrowingWindowMovesFirstAndAShrinkingOneResizesFirst(
    frame: CGRect, calls: [FakeAXClient.Call]
  ) async throws {
    let harness = await started()
    try harness.windowSystem.setFrameInPassing(frame, of: WindowID(1))
    #expect(harness.accessibility.calls(on: 1) == calls)
  }

  @Test func inPassingAWindowThatGrowsOneWayAndShrinksTheOtherIsSetInFull() async throws {
    let harness = await started()
    let frame = CGRect(x: 100, y: 150, width: 500, height: 200)
    try harness.windowSystem.setFrameInPassing(frame, of: WindowID(1))
    #expect(harness.accessibility.calls(on: 1).count == 3)
  }
}
