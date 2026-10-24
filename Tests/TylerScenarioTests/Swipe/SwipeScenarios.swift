import CoreGraphics
import Testing
import TylerConfig
import TylerCore
import TylerTestSupport

@testable import TylerServer

/// Sliding between workspaces with a trackpad swipe. Window 1 fills workspace 1, window 2
/// workspace 2 and window 3 workspace 4, the one before workspace 1, each parked from its slot.
/// With the default `swipe-distance` of 0.3, a swipe of 0.15 trackpad widths moves the content
/// half a display.
@Suite("Workspaces: trackpad swipe")
@MainActor
struct SwipeScenarios {
  private let area = FakeDisplays.main.visibleFrame

  private func scenario(
    config: Config = Config(), animates: Bool = false, configFile: FakeConfigFile? = nil
  ) async -> Scenario {
    let scenario = await Scenario(
      openAtStart: spread([1, 2, 3]), config: config, configFile: configFile,
      animates: animates, slide: .milliseconds(48), frameInterval: .milliseconds(16))
    if config.workspaces.count >= 4 {
      await scenario.focus(2)
      await scenario.command("window move-to-workspace 2")
      await scenario.focus(3)
      await scenario.command("window move-to-workspace 4")
    }
    scenario.windowSystem.clearRecordedCalls()
    return scenario
  }

  /// Sends swipe updates and lets tylerd handle them, without letting time pass.
  private func swipe(_ updates: SwipeUpdate..., in scenario: Scenario) async {
    for update in updates { scenario.pointer.swipe(update) }
    await scenario.harness.settle()
  }

  /// Lets the swipe's frame pacing move on to the next frame.
  private func nextFrame(_ scenario: Scenario) async {
    await scenario.wait(Animator.defaultFrameInterval)
  }

  private func lastNudge(of windowID: UInt32, in scenario: Scenario) -> CGPoint? {
    scenario.windowSystem.nudges.last { $0.id == WindowID(windowID) }?.origin
  }

  @Test func theWindowsFollowTheFingers() async {
    let scenario = await scenario()
    await swipe(.began, .moved(offset: -0.15), in: scenario)
    let leaving = Track.leaving(
      WindowID(1), from: area, direction: .next, on: FakeDisplays.main)
    let entering = Track.entering(
      WindowID(2), into: area, direction: .next, on: FakeDisplays.main)
    #expect(lastNudge(of: 1, in: scenario) == leaving.position(at: 0.5, easing: Easing.linear))
    #expect(lastNudge(of: 2, in: scenario) == entering.position(at: 0.5, easing: Easing.linear))
    #expect(lastNudge(of: 3, in: scenario) == nil, "the other neighbour stays parked")
    #expect(scenario.shown == [1], "nothing is decided before the release")
  }

  @Test func aReleasePastHalfwayBringsTheNextWorkspaceIn() async {
    let scenario = await scenario()
    await swipe(.began, .moved(offset: -0.18), .ended(velocity: 0), in: scenario)
    #expect(scenario.shown == [2])
    #expect(scenario.frame(of: 2) == area)
    #expect(scenario.isParked(1))
    #expect(scenario.isParked(3))
    #expect(scenario.windowSystem.focusCalls.last == WindowID(2))
  }

  @Test func aReleaseBeforeHalfwayGoesBack() async {
    let scenario = await scenario()
    await swipe(.began, .moved(offset: -0.06), .ended(velocity: 0), in: scenario)
    #expect(scenario.shown == [1])
    #expect(scenario.frame(of: 1) == area)
    #expect(scenario.isParked(2))
    #expect(scenario.isParked(3))
  }

  @Test func aFlickGoesOnEvenBeforeHalfway() async {
    let scenario = await scenario()
    // 0.6 trackpad widths per second is two display widths per second.
    await swipe(.began, .moved(offset: -0.06), .ended(velocity: -0.6), in: scenario)
    #expect(scenario.shown == [2])
    #expect(scenario.frame(of: 2) == area)
  }

  @Test func swipingRightFromTheFirstWorkspaceWrapsToTheLast() async {
    let scenario = await scenario()
    await swipe(.began, .moved(offset: 0.18), .ended(velocity: 0), in: scenario)
    #expect(scenario.shown == [4])
    #expect(scenario.frame(of: 3) == area)
    #expect(scenario.isParked(1))
    #expect(scenario.isParked(2))
  }

  @Test func turningBackPastTheStartSwapsTheNeighbour() async {
    let scenario = await scenario()
    await swipe(.began, .moved(offset: -0.15), in: scenario)
    await swipe(.moved(offset: 0.15), in: scenario)
    await nextFrame(scenario)
    #expect(scenario.isParked(2), "the next workspace went back")
    let entering = Track.entering(
      WindowID(3), into: area, direction: .prev, on: FakeDisplays.main)
    #expect(lastNudge(of: 3, in: scenario) == entering.position(at: 0.5, easing: Easing.linear))
    #expect(scenario.harness.everyPositionIsAllowed())
  }

  @Test func offsetsWithinAFrameReplaceEachOther() async {
    let scenario = await scenario()
    await swipe(
      .began, .moved(offset: -0.03), .moved(offset: -0.06), .moved(offset: -0.09), in: scenario)
    #expect(scenario.windowSystem.nudges.filter { $0.id == WindowID(1) }.count == 1)
    await nextFrame(scenario)
    let leaving = Track.leaving(
      WindowID(1), from: area, direction: .next, on: FakeDisplays.main)
    let steps = scenario.windowSystem.nudges.filter { $0.id == WindowID(1) }
    #expect(steps.count == 2, "the middle offset was never placed")
    #expect(steps.last?.origin == leaving.position(at: 0.3, easing: Easing.linear))
    await nextFrame(scenario)
    #expect(scenario.windowSystem.nudges.filter { $0.id == WindowID(1) }.count == 2, "nothing new")
  }

  @Test func aSlowStepIsFollowedByTheNextAtOnce() async {
    let scenario = await scenario()
    scenario.windowSystem.onWrite = { [clock = scenario.clock] in
      clock.advance(by: .milliseconds(5))
    }
    await swipe(.began, .moved(offset: -0.03), in: scenario)
    scenario.windowSystem.onWrite = nil
    await swipe(.moved(offset: -0.06), in: scenario)
    #expect(
      scenario.windowSystem.nudges.filter { $0.id == WindowID(1) }.count == 2,
      "the first step took longer than a frame")
  }

  @Test func aCommandInTheMiddlePutsTheWindowsBack() async {
    let scenario = await scenario()
    await swipe(.began, .moved(offset: -0.15), in: scenario)
    await scenario.start("workspace retile")
    #expect(scenario.frame(of: 1) == area)
    #expect(scenario.isParked(2))
    await swipe(.moved(offset: -0.2), .ended(velocity: 0), in: scenario)
    #expect(scenario.shown == [1], "the rest of the swipe is ignored")
    #expect(scenario.frame(of: 1) == area)
  }

  @Test func theSlideFinishesFromWhereTheFingersLeftIt() async {
    let scenario = await scenario(animates: true)
    await swipe(.began, .moved(offset: -0.18), .ended(velocity: 0), in: scenario)
    await scenario.runUntilQuiet()
    let steps = scenario.windowSystem.nudges.filter { $0.id == WindowID(1) }.map(\.origin.x)
    #expect(steps.count >= 2)
    #expect(steps == steps.sorted(by: >), "it carries on to the left")
    #expect(scenario.isParked(1))
    #expect(scenario.frame(of: 2) == area)
    #expect(scenario.harness.everyPositionIsAllowed())
  }

  @Test func goingBackFromNearTheStartStillSlides() async {
    let scenario = await scenario(animates: true)
    await swipe(.began, .moved(offset: -0.03), .ended(velocity: 0), in: scenario)
    scenario.windowSystem.clearRecordedCalls()
    await scenario.runUntilQuiet()
    let steps = scenario.windowSystem.nudges.filter { $0.id == WindowID(1) }.map(\.origin.x)
    #expect(!steps.isEmpty, "a tenth of the way back would otherwise snap in one frame")
    #expect(steps == steps.sorted(), "it moves back to the right")
    #expect(scenario.frame(of: 1) == area)
    #expect(scenario.isParked(2))
  }

  @Test(arguments: ["swipe off", "one workspace", "tiling off"])
  func panningCanBeOff(reason: String) async {
    var config = Config()
    if reason == "swipe off" { config.gestures.swipe = false }
    if reason == "one workspace" { config.workspaces.count = 1 }
    let scenario = await scenario(config: config)
    if reason == "tiling off" { await scenario.command("tiling off") }
    scenario.windowSystem.clearRecordedCalls()
    await swipe(.began, .moved(offset: -0.18), .ended(velocity: 0), in: scenario)
    #expect(scenario.windowSystem.nudges.isEmpty)
    #expect(scenario.windowSystem.moves.isEmpty)
    #expect(scenario.shown == [1])
  }

  // MARK: - Watching the trackpad

  @Test func thePointerWatchesForTheConfiguredSwipe() async {
    var config = Config()
    config.gestures.fingers = 4
    let scenario = await scenario(config: config)
    #expect(scenario.pointer.swipeFingers == 4)
  }

  @Test func reloadTurnsTheSwipeOffAndOnAgain() async {
    let file = FakeConfigFile()
    let scenario = await scenario(configFile: file)
    #expect(scenario.pointer.swipeFingers == 3)
    var config = Config()
    config.gestures.swipe = false
    file.write(.config(config))
    await scenario.command("config reload")
    #expect(scenario.pointer.swipeFingers == nil)
    file.write(.missing)
    await scenario.command("config reload")
    #expect(scenario.pointer.swipeFingers == 3, "no file means the defaults")
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
