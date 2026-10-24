import CoreGraphics
import Testing
import TylerCore
import TylerTestSupport

/// Swiping along a strip of three half windows. The two views are 873 points apart; with the
/// default `swipe-distance` of 0.3, a swipe of 0.075 trackpad widths moves the content a quarter of
/// the display, about half a column.
@Suite("Strip layout: trackpad swipe")
@MainActor
struct StripSwipeScenarios {
  /// Windows 1, 2 and 3 in the strip, window 1 focused; or only windows 1 and 2, which fit.
  private func strip(_ ids: [UInt32] = [1, 2, 3]) async -> Scenario {
    let scenario = await Scenario(workspaces: [1: ids], layout: .strip)
    await scenario.focus(1)
    scenario.windowSystem.clearRecordedCalls()
    return scenario
  }

  private func swipe(_ updates: SwipeUpdate..., in scenario: Scenario) async {
    for update in updates { scenario.pointer.swipe(update) }
    await scenario.harness.settle()
  }

  /// Windows 2 and 3 in view, window 1 parked.
  private func expectSecondView(_ scenario: Scenario) {
    #expect(scenario.isParked(1))
    #expect(scenario.frame(of: 2) == scenario.rect(.leftHalf))
    #expect(scenario.frame(of: 3) == scenario.rect(.rightHalf))
  }

  /// Windows 1 and 2 in view, window 3 parked.
  private func expectFirstView(_ scenario: Scenario) {
    #expect(scenario.frame(of: 1) == scenario.rect(.leftHalf))
    #expect(scenario.frame(of: 2) == scenario.rect(.rightHalf))
    #expect(scenario.isParked(3))
  }

  @Test func theWindowsFollowTheFingers() async throws {
    let scenario = await strip()
    let parked = try #require(scenario.frame(of: 3))
    let first = scenario.frame(of: 1)
    await swipe(.began, .moved(offset: -0.075), in: scenario)
    let incoming = try #require(scenario.frame(of: 3))
    #expect(incoming.minX < parked.minX, "window 3 comes in from the right")
    #expect(incoming.minX > scenario.rect(.rightHalf).minX, "but only part of the way")
    #expect(scenario.shown == [1])
    await swipe(.ended(velocity: 0), in: scenario)
    #expect(scenario.frame(of: 1) == first, "nothing was decided before the release")
    let leaving = scenario.windowSystem.moves.filter { $0.id == WindowID(1) }.map(\.frame.size)
    #expect(
      leaving.allSatisfy { $0 == scenario.rect(.leftHalf).size },
      "the leaving window keeps its size")
  }

  @Test func aReleasePastHalfwaySettlesOnTheNextView() async {
    let scenario = await strip()
    await swipe(.began, .moved(offset: -0.1), .ended(velocity: 0), in: scenario)
    expectSecondView(scenario)
    #expect(scenario.windowSystem.focusCalls.last == WindowID(2), "focus moves into the view")
    #expect(scenario.shown == [1], "the swipe stays on this workspace")
  }

  @Test func aReleaseBeforeHalfwayGoesBack() async {
    let scenario = await strip()
    await swipe(.began, .moved(offset: -0.03), .ended(velocity: 0), in: scenario)
    expectFirstView(scenario)
    #expect(scenario.windowSystem.focusCalls.isEmpty)
  }

  @Test func aFlickGoesOn() async {
    let scenario = await strip()
    await swipe(.began, .moved(offset: -0.03), .ended(velocity: -1), in: scenario)
    expectSecondView(scenario)
  }

  @Test func panningPastTheEndStopsThere() async {
    let scenario = await strip()
    await swipe(.began, .moved(offset: -1), .ended(velocity: 0), in: scenario)
    expectSecondView(scenario)
    #expect(scenario.harness.everyPositionIsAllowed())
  }

  @Test func panningBackFromTheStartMovesNothing() async {
    let scenario = await strip()
    await swipe(.began, .moved(offset: 0.1), .ended(velocity: 1), in: scenario)
    expectFirstView(scenario)
    #expect(scenario.windowSystem.moves.isEmpty)
    #expect(scenario.windowSystem.nudges.isEmpty)
  }

  @Test func aStripThatFitsNeverSwitchesWorkspaces() async {
    let scenario = await strip([1, 2])
    await swipe(.began, .moved(offset: -0.2), .ended(velocity: -1), in: scenario)
    #expect(scenario.shown == [1])
    #expect(scenario.windowSystem.moves.isEmpty)
  }

  @Test func aCommandMidSwipePutsTheWindowsBack() async {
    let scenario = await strip()
    await swipe(.began, .moved(offset: -0.075), in: scenario)
    await scenario.start("workspace retile")
    expectFirstView(scenario)
  }
}
