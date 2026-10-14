import CoreGraphics
import Testing
import TylerCore
import TylerTestSupport

@testable import TylerServer

/// Swiping along a strip of three half windows. The two views are 873 points apart; with the
/// default `swipe-distance` of 0.3, a swipe of 0.075 trackpad widths moves the content a quarter of
/// the display, about half a column.
@Suite("Strip layout: trackpad swipe")
@MainActor
struct StripSwipeScenarios {
  private let pointer = FakePointer()
  private let clock = TestClock()
  private let halves = TallLayout().frames(count: 2, in: FakeDisplays.main.visibleFrame)

  /// Windows 1, 2 and 3 in the strip, window 1 focused; or only windows 1 and 2, which fit.
  private func strip(_ ids: [UInt32] = [1, 2, 3]) async -> ManagerHarness {
    let harness = ManagerHarness(ids, pointer: pointer, clock: clock)
    await harness.osFocus(1)
    _ = harness.manager.setLayout(.set(.strip))
    await harness.settle()
    harness.backend.clearRecordedCalls()
    return harness
  }

  private func swipe(_ updates: SwipeUpdate..., in harness: ManagerHarness) async {
    for update in updates { pointer.swipe(update) }
    await harness.settle()
  }

  /// Windows 2 and 3 in view, window 1 parked.
  private func expectSecondView(_ harness: ManagerHarness) {
    #expect(harness.isParked(1))
    #expect(harness.frame(of: 2) == halves[0])
    #expect(harness.frame(of: 3) == halves[1])
  }

  /// Windows 1 and 2 in view, window 3 parked.
  private func expectFirstView(_ harness: ManagerHarness) {
    #expect(harness.frame(of: 1) == halves[0])
    #expect(harness.frame(of: 2) == halves[1])
    #expect(harness.isParked(3))
  }

  @Test func theWindowsFollowTheFingers() async throws {
    let harness = await strip()
    let parked = try #require(harness.frame(of: 3))
    await swipe(.began, .moved(offset: -0.075), in: harness)
    let incoming = try #require(harness.frame(of: 3))
    #expect(incoming.minX < parked.minX, "window 3 comes in from the right")
    #expect(incoming.minX > halves[1].minX, "but only part of the way")
    #expect(harness.manager.workspaces.currentIndex == 0)
    #expect(harness.manager.workspaces.current.firstVisible == WindowID(1), "nothing decided yet")
    let leaving = harness.backend.moves.filter { $0.id == WindowID(1) }.map(\.frame.size)
    #expect(leaving.allSatisfy { $0 == halves[0].size }, "the leaving window keeps its size")
  }

  @Test func aReleasePastHalfwaySettlesOnTheNextView() async {
    let harness = await strip()
    await swipe(.began, .moved(offset: -0.1), .ended(velocity: 0), in: harness)
    expectSecondView(harness)
    #expect(harness.backend.focusCalls.last == WindowID(2), "focus moves into the view")
    #expect(harness.manager.workspaces.currentIndex == 0, "the swipe stays on this workspace")
  }

  @Test func aReleaseBeforeHalfwayGoesBack() async {
    let harness = await strip()
    await swipe(.began, .moved(offset: -0.03), .ended(velocity: 0), in: harness)
    expectFirstView(harness)
    #expect(harness.backend.focusCalls.isEmpty)
  }

  @Test func aFlickGoesOn() async {
    let harness = await strip()
    await swipe(.began, .moved(offset: -0.03), .ended(velocity: -1), in: harness)
    expectSecondView(harness)
  }

  @Test func panningPastTheEndStopsThere() async {
    let harness = await strip()
    await swipe(.began, .moved(offset: -1), .ended(velocity: 0), in: harness)
    expectSecondView(harness)
    #expect(harness.everyPositionIsAllowed())
  }

  @Test func panningBackFromTheStartMovesNothing() async {
    let harness = await strip()
    await swipe(.began, .moved(offset: 0.1), .ended(velocity: 1), in: harness)
    expectFirstView(harness)
    #expect(harness.backend.moves.isEmpty)
    #expect(harness.backend.nudges.isEmpty)
  }

  @Test func aStripThatFitsNeverSwitchesWorkspaces() async {
    let harness = await strip([1, 2])
    await swipe(.began, .moved(offset: -0.2), .ended(velocity: -1), in: harness)
    #expect(harness.manager.workspaces.currentIndex == 0)
    #expect(harness.backend.moves.isEmpty)
  }

  @Test func aCommandMidSwipePutsTheWindowsBack() async {
    let harness = await strip()
    await swipe(.began, .moved(offset: -0.075), in: harness)
    _ = harness.manager.retile()
    expectFirstView(harness)
  }
}
