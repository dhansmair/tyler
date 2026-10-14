import CoreGraphics
import Testing
import TylerConfig
import TylerCore
import TylerTestSupport

@testable import TylerServer

/// Sliding between workspaces with a trackpad swipe. Window 1 fills workspace 1, window 2
/// workspace 2 and window 3 workspace 4, the one before workspace 1. With the default
/// `swipe-distance` of 0.3, a swipe of 0.15 trackpad widths moves the content half a display.
@Suite("Workspaces: trackpad swipe")
@MainActor
struct SwipeScenarios {
  private let pointer = FakePointer()
  private let clock = TestClock()

  private func makeHarness(
    config: Config = Config(), animator: Animator = .snap, configFile: FakeConfigFile? = nil
  ) async -> ManagerHarness {
    let harness = ManagerHarness(
      [1, 2, 3], animator: animator, config: config, configFile: configFile, pointer: pointer,
      clock: clock)
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

  /// Sends swipe updates and lets the manager handle them.
  private func swipe(_ updates: SwipeUpdate..., in harness: ManagerHarness) async {
    for update in updates { pointer.swipe(update) }
    await harness.settle()
  }

  /// Lets the swipe's frame pacing move on to the next frame.
  private func nextFrame(_ harness: ManagerHarness) async {
    clock.advance(by: Animator.defaultFrameInterval)
    await harness.settle()
  }

  private func lastNudge(of windowID: UInt32, in harness: ManagerHarness) -> CGPoint? {
    harness.backend.nudges.last { $0.id == WindowID(windowID) }?.origin
  }

  @Test func theWindowsFollowTheFingers() async {
    let harness = await makeHarness()
    await swipe(.began, .moved(offset: -0.15), in: harness)
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
    await swipe(.began, .moved(offset: -0.18), .ended(velocity: 0), in: harness)
    #expect(harness.manager.workspaces.currentIndex == 1)
    #expect(harness.frame(of: 2) == harness.area)
    #expect(harness.isParked(1))
    #expect(harness.isParked(3))
    #expect(harness.backend.focusCalls.last == WindowID(2))
  }

  @Test func aReleaseBeforeHalfwayGoesBack() async {
    let harness = await makeHarness()
    await swipe(.began, .moved(offset: -0.06), .ended(velocity: 0), in: harness)
    #expect(harness.manager.workspaces.currentIndex == 0)
    #expect(harness.frame(of: 1) == harness.area)
    #expect(harness.isParked(2))
    #expect(harness.isParked(3))
  }

  @Test func aFlickGoesOnEvenBeforeHalfway() async {
    let harness = await makeHarness()
    // 0.6 trackpad widths per second is two display widths per second.
    await swipe(.began, .moved(offset: -0.06), .ended(velocity: -0.6), in: harness)
    #expect(harness.manager.workspaces.currentIndex == 1)
    #expect(harness.frame(of: 2) == harness.area)
  }

  @Test func swipingRightFromTheFirstWorkspaceWrapsToTheLast() async {
    let harness = await makeHarness()
    await swipe(.began, .moved(offset: 0.18), .ended(velocity: 0), in: harness)
    #expect(harness.manager.workspaces.currentIndex == 3)
    #expect(harness.frame(of: 3) == harness.area)
    #expect(harness.isParked(1))
    #expect(harness.isParked(2))
  }

  @Test func turningBackPastTheStartSwapsTheNeighbour() async {
    let harness = await makeHarness()
    await swipe(.began, .moved(offset: -0.15), in: harness)
    await swipe(.moved(offset: 0.15), in: harness)
    await nextFrame(harness)
    #expect(harness.isParked(2), "the next workspace went back")
    let entering = Track.entering(
      WindowID(3), into: harness.area, direction: .prev, on: harness.display)
    #expect(lastNudge(of: 3, in: harness) == entering.position(at: 0.5, easing: Easing.linear))
    #expect(harness.everyPositionIsAllowed())
  }

  @Test func offsetsWithinAFrameReplaceEachOther() async {
    let harness = await makeHarness()
    await swipe(
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

  @Test func aSlowStepIsFollowedByTheNextAtOnce() async {
    let harness = await makeHarness()
    harness.backend.onWrite = { [clock] in clock.advance(by: .milliseconds(5)) }
    await swipe(.began, .moved(offset: -0.03), in: harness)
    harness.backend.onWrite = nil
    await swipe(.moved(offset: -0.06), in: harness)
    #expect(
      harness.backend.nudges.filter { $0.id == WindowID(1) }.count == 2,
      "the first step took longer than a frame")
  }

  @Test func aCommandInTheMiddlePutsTheWindowsBack() async {
    let harness = await makeHarness()
    await swipe(.began, .moved(offset: -0.15), in: harness)
    _ = harness.manager.retile()
    #expect(harness.frame(of: 1) == harness.area)
    #expect(harness.isParked(2))
    await swipe(.moved(offset: -0.2), .ended(velocity: 0), in: harness)
    #expect(harness.manager.workspaces.currentIndex == 0, "the rest of the swipe is ignored")
    #expect(harness.frame(of: 1) == harness.area)
  }

  @Test func theSlideFinishesFromWhereTheFingersLeftIt() async {
    let animator = Animator(
      duration: .milliseconds(48), frameInterval: .milliseconds(16), clock: clock)
    let harness = await makeHarness(animator: animator)
    await swipe(.began, .moved(offset: -0.18), .ended(velocity: 0), in: harness)
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

  @Test func goingBackFromNearTheStartStillSlides() async {
    let animator = Animator(
      duration: .milliseconds(48), frameInterval: .milliseconds(16), clock: clock)
    let harness = await makeHarness(animator: animator)
    await swipe(.began, .moved(offset: -0.03), .ended(velocity: 0), in: harness)
    harness.backend.clearRecordedCalls()
    while clock.hasSleepers {
      clock.advance(by: .milliseconds(16))
      await harness.settle()
    }
    let steps = harness.backend.nudges.filter { $0.id == WindowID(1) }.map(\.origin.x)
    #expect(!steps.isEmpty, "a tenth of the way back would otherwise snap in one frame")
    #expect(steps == steps.sorted(), "it moves back to the right")
    #expect(harness.frame(of: 1) == harness.area)
    #expect(harness.isParked(2))
  }

  @Test(arguments: ["swipe off", "one workspace", "tiling off"])
  func panningCanBeOff(reason: String) async {
    var config = Config()
    if reason == "swipe off" { config.gestures.swipe = false }
    if reason == "one workspace" { config.workspaces.count = 1 }
    let harness = await makeHarness(config: config)
    if reason == "tiling off" { _ = harness.manager.setTiling(.off) }
    harness.backend.clearRecordedCalls()
    await swipe(.began, .moved(offset: -0.18), .ended(velocity: 0), in: harness)
    #expect(harness.backend.nudges.isEmpty)
    #expect(harness.backend.moves.isEmpty)
    #expect(harness.manager.workspaces.currentIndex == 0)
  }

  // MARK: - Watching the trackpad

  @Test func thePointerWatchesForTheConfiguredSwipe() async {
    var config = Config()
    config.gestures.fingers = 4
    _ = await makeHarness(config: config)
    #expect(pointer.swipeFingers == 4)
  }

  @Test func reloadTurnsTheSwipeOffAndOnAgain() async {
    let file = FakeConfigFile()
    let harness = await makeHarness(configFile: file)
    #expect(pointer.swipeFingers == 3)
    var config = Config()
    config.gestures.swipe = false
    file.write(.config(config))
    _ = harness.manager.reload()
    #expect(pointer.swipeFingers == nil)
    file.write(.missing)
    _ = harness.manager.reload()
    #expect(pointer.swipeFingers == 3, "no file means the defaults")
  }

  @Test func movingTheFingersLeftBringsInTheNextWorkspace() async {
    let scenario = await Scenario(workspaces: [1: [1, 2], 2: [3]])
    await scenario.swipe(.left)
    #expect(scenario.shown == [2])
    #expect(scenario.frame(of: 3) == scenario.rect(.full))
    #expect(scenario.isParked(1))
    #expect(scenario.isParked(2))
    #expect(scenario.focused == 3)
  }

  @Test func movingTheFingersRightFromTheFirstWorkspaceWrapsToTheLast() async {
    let scenario = await Scenario(workspaces: [1: [1], 4: [2]])
    await scenario.swipe(.right)
    #expect(scenario.shown == [4])
    #expect(scenario.frame(of: 2) == scenario.rect(.full))
    #expect(scenario.isParked(1))
  }
}
