import CoreGraphics
import Testing
import TylerCore

@testable import TylerServer

/// Sliding between workspaces with a trackpad swipe. Window 1 fills workspace 1, window 2
/// workspace 2 and window 3 workspace 4, the one before workspace 1. With the default
/// `swipe-distance` of 0.3, a pan of 0.15 trackpad widths moves the content half a display.
@Suite("Workspaces: trackpad pan")
@MainActor
struct PanTests {
  private let pointer = FakePointer()
  private let clock = TestClock()

  private func makeHarness(
    config: Config = Config(), animator: Animator = .snap
  ) async -> WorkspaceHarness {
    let harness = WorkspaceHarness(
      [1, 2, 3], animator: animator, config: config, pointer: pointer, clock: clock)
    if config.workspaces.count >= 4 {
      await harness.osFocus(2)
      _ = harness.manager.moveToWorkspace(.number(2), follow: false)
      await harness.osFocus(3)
      _ = harness.manager.moveToWorkspace(.number(4), follow: false)
    }
    await harness.settle()
    harness.backend.clearRecordedCalls()
    return harness
  }

  /// Sends pan updates and lets the manager handle them.
  private func pan(_ updates: PanUpdate..., in harness: WorkspaceHarness) async {
    for update in updates { pointer.pan(update) }
    await harness.settle()
  }

  /// Lets the pan's frame pacing move on to the next frame.
  private func nextFrame(_ harness: WorkspaceHarness) async {
    clock.advance(by: Animator.defaultFrameInterval)
    await harness.settle()
  }

  private func lastNudge(of windowID: UInt32, in harness: WorkspaceHarness) -> CGPoint? {
    harness.backend.nudges.last { $0.id == WindowID(windowID) }?.origin
  }

  @Test func theWindowsFollowTheFingers() async {
    let harness = await makeHarness()
    await pan(.began, .moved(offset: -0.15), in: harness)
    let leaving = Track.leaving(
      WindowID(1), from: harness.area, direction: .next, on: harness.display)
    let entering = Track.entering(
      WindowID(2), into: harness.area, direction: .next, on: harness.display)
    #expect(lastNudge(of: 1, in: harness) == leaving.position(at: 0.5, easing: Easing.linear))
    #expect(lastNudge(of: 2, in: harness) == entering.position(at: 0.5, easing: Easing.linear))
    #expect(lastNudge(of: 3, in: harness) == nil, "the other neighbour stays parked")
    #expect(harness.manager.workspaces.currentIndex == 0, "nothing is decided before the release")
  }

  @Test func aReleasePastHalfwayBringsTheNextWorkspaceIn() async {
    let harness = await makeHarness()
    await pan(.began, .moved(offset: -0.18), .ended(velocity: 0), in: harness)
    #expect(harness.manager.workspaces.currentIndex == 1)
    #expect(harness.frame(of: 2) == harness.area)
    #expect(harness.isParked(1))
    #expect(harness.isParked(3))
    #expect(harness.backend.focusCalls.last == WindowID(2))
  }

  @Test func aReleaseBeforeHalfwayGoesBack() async {
    let harness = await makeHarness()
    await pan(.began, .moved(offset: -0.06), .ended(velocity: 0), in: harness)
    #expect(harness.manager.workspaces.currentIndex == 0)
    #expect(harness.frame(of: 1) == harness.area)
    #expect(harness.isParked(2))
    #expect(harness.isParked(3))
  }

  @Test func aFlickGoesOnEvenBeforeHalfway() async {
    let harness = await makeHarness()
    // 0.6 trackpad widths per second is two display widths per second.
    await pan(.began, .moved(offset: -0.06), .ended(velocity: -0.6), in: harness)
    #expect(harness.manager.workspaces.currentIndex == 1)
    #expect(harness.frame(of: 2) == harness.area)
  }

  @Test func swipingRightFromTheFirstWorkspaceWrapsToTheLast() async {
    let harness = await makeHarness()
    await pan(.began, .moved(offset: 0.18), .ended(velocity: 0), in: harness)
    #expect(harness.manager.workspaces.currentIndex == 3)
    #expect(harness.frame(of: 3) == harness.area)
    #expect(harness.isParked(1))
    #expect(harness.isParked(2))
  }

  @Test func turningBackPastTheStartSwapsTheNeighbour() async {
    let harness = await makeHarness()
    await pan(.began, .moved(offset: -0.15), in: harness)
    await pan(.moved(offset: 0.15), in: harness)
    await nextFrame(harness)
    #expect(harness.isParked(2), "the next workspace went back")
    let entering = Track.entering(
      WindowID(3), into: harness.area, direction: .prev, on: harness.display)
    #expect(lastNudge(of: 3, in: harness) == entering.position(at: 0.5, easing: Easing.linear))
    #expect(harness.everyPositionIsAllowed())
  }

  @Test func offsetsWithinAFrameReplaceEachOther() async {
    let harness = await makeHarness()
    await pan(
      .began, .moved(offset: -0.03), .moved(offset: -0.06), .moved(offset: -0.09), in: harness)
    #expect(harness.backend.nudges.filter { $0.id == WindowID(1) }.count == 1)
    await nextFrame(harness)
    let leaving = Track.leaving(
      WindowID(1), from: harness.area, direction: .next, on: harness.display)
    let steps = harness.backend.nudges.filter { $0.id == WindowID(1) }
    #expect(steps.count == 2, "the middle offset was never placed")
    #expect(steps.last?.origin == leaving.position(at: 0.3, easing: Easing.linear))
    await nextFrame(harness)
    #expect(harness.backend.nudges.filter { $0.id == WindowID(1) }.count == 2, "nothing new")
  }

  @Test func aCommandInTheMiddlePutsTheWindowsBack() async {
    let harness = await makeHarness()
    await pan(.began, .moved(offset: -0.15), in: harness)
    _ = harness.manager.retile()
    #expect(harness.frame(of: 1) == harness.area)
    #expect(harness.isParked(2))
    await pan(.moved(offset: -0.2), .ended(velocity: 0), in: harness)
    #expect(harness.manager.workspaces.currentIndex == 0, "the rest of the pan is ignored")
    #expect(harness.frame(of: 1) == harness.area)
  }

  @Test func theSlideFinishesFromWhereTheFingersLeftIt() async {
    let animator = Animator(
      duration: .milliseconds(48), frameInterval: .milliseconds(16), clock: clock)
    let harness = await makeHarness(animator: animator)
    await pan(.began, .moved(offset: -0.18), .ended(velocity: 0), in: harness)
    while clock.hasSleepers {
      clock.advance(by: .milliseconds(16))
      await harness.settle()
    }
    let steps = harness.backend.nudges.filter { $0.id == WindowID(1) }.map(\.origin.x)
    #expect(steps.count >= 2)
    #expect(steps == steps.sorted(by: >), "it carries on to the left")
    #expect(harness.isParked(1))
    #expect(harness.frame(of: 2) == harness.area)
    #expect(harness.everyPositionIsAllowed())
  }

  @Test(arguments: ["swipe off", "one workspace", "tiling off"])
  func panningCanBeOff(reason: String) async {
    var config = Config()
    if reason == "swipe off" { config.gestures.swipe = false }
    if reason == "one workspace" { config.workspaces.count = 1 }
    let harness = await makeHarness(config: config)
    if reason == "tiling off" { _ = harness.manager.setTiling(.off) }
    harness.backend.clearRecordedCalls()
    await pan(.began, .moved(offset: -0.18), .ended(velocity: 0), in: harness)
    #expect(harness.backend.nudges.isEmpty)
    #expect(harness.backend.moves.isEmpty)
    #expect(harness.manager.workspaces.currentIndex == 0)
  }
}
