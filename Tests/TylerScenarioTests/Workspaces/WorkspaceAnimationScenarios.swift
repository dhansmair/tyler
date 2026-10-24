import CoreGraphics
import Testing
import TylerCore
import TylerTestSupport

@testable import TylerServer

@Suite("Workspaces: animation")
@MainActor
struct WorkspaceAnimationScenarios {
  /// Three frames of 16 ms: two intermediate steps, then the final placement.
  private func scenario(
    displays: [DisplayInfo] = [FakeDisplays.main], workspaces: [Int: [UInt32]]
  ) async -> Scenario {
    await Scenario(
      displays: displays, workspaces: workspaces, animates: true, slide: .milliseconds(48),
      frameInterval: .milliseconds(16))
  }

  @Test func outgoingWindowsSlideLeftThenPark() async throws {
    let scenario = await scenario(workspaces: [1: [1, 2]])
    let start = try #require(scenario.frame(of: 1))
    scenario.windowSystem.clearRecordedCalls()
    await scenario.start("workspace focus next")
    #expect(scenario.frame(of: 1) == start, "nothing moves before the first frame")

    await scenario.runUntilQuiet()
    let steps = scenario.windowSystem.nudges.filter { $0.id == WindowID(1) }.map(\.origin)
    #expect(steps.count == 2)
    #expect(steps.allSatisfy { $0.x < start.minX }, "going to the next workspace slides left")
    #expect(steps.allSatisfy { $0.y == start.minY }, "nothing moves vertically")
    #expect(scenario.isParked(1))
    #expect(scenario.isParked(2))
  }

  @Test func incomingWindowsStartWhereTheyAreParkedAndEndInTheirSlots() async {
    // Parked from its slot, so it has the size of a tiled window.
    let scenario = await scenario(workspaces: [1: [1, 2]])
    await scenario.focus(2)
    await scenario.command("window move-to-workspace next")
    let parked = scenario.frame(of: 2)
    scenario.windowSystem.clearRecordedCalls()

    await scenario.start("workspace focus next")
    let first = scenario.windowSystem.moves.first { $0.id == WindowID(2) }
    #expect(first?.frame.origin == parked?.origin, "resized to its slot while still parked")
    #expect(first?.frame.size == scenario.rect(.full).size)
    await scenario.runUntilQuiet()
    let steps = scenario.windowSystem.nudges.filter { $0.id == WindowID(2) }.map(\.origin.x)
    #expect(steps == steps.sorted(by: >), "it comes in from the right")
    #expect(scenario.frame(of: 2) == scenario.rect(.full))
  }

  @Test func besideADisplayToTheRightSwitchesAreInstant() async throws {
    let scenario = await scenario(
      displays: [FakeDisplays.main, FakeDisplays.right], workspaces: [1: [1, 2]])
    await scenario.focus(2)
    scenario.windowSystem.clearRecordedCalls()
    await scenario.command("window move-to-workspace next")
    #expect(scenario.windowSystem.nudges.isEmpty, "sent off by a jump")
    #expect(scenario.frame(of: 2)?.maxX == scenario.rect(.full).minX + 1, "parked at the left edge")

    await scenario.command("workspace focus next")
    await scenario.command("workspace focus prev")
    #expect(scenario.windowSystem.nudges.isEmpty, "nothing slides either way")
    #expect(scenario.frame(of: 1) == scenario.rect(.full))
    #expect(scenario.isParked(2))
  }

  @Test func scrollingUpMovesTheOtherWay() async throws {
    let scenario = await scenario(workspaces: [1: [1]])
    let start = try #require(scenario.frame(of: 1))
    scenario.windowSystem.clearRecordedCalls()
    await scenario.command("workspace focus prev")
    let steps = scenario.windowSystem.nudges.map(\.origin)
    #expect(!steps.isEmpty)
    #expect(steps.allSatisfy { $0.x > start.minX })
  }

  @Test(arguments: [("next", true), ("prev", false)])
  func aSentWindowTravelsTowardsItsWorkspace(target: String, right: Bool) async throws {
    let scenario = await scenario(workspaces: [1: [1, 2]])
    await scenario.focus(2)
    let start = try #require(scenario.frame(of: 2))
    scenario.windowSystem.clearRecordedCalls()
    await scenario.command("window move-to-workspace \(target)")
    let steps = scenario.windowSystem.nudges.filter { $0.id == WindowID(2) }.map(\.origin.x)
    #expect(!steps.isEmpty)
    #expect(steps.allSatisfy { right ? $0 > start.minX : $0 < start.minX })
    #expect(scenario.isParked(2))
  }

  @Test(arguments: [("next", "prev", 2), ("prev", "next", 4)])
  func noWindowIsAskedForAPositionMacOSWouldPullBack(
    there: String, back: String, other: Int
  ) async {
    // Two workspaces with several windows each, so windows enter and leave together.
    let scenario = await scenario(workspaces: [1: [1, 2], other: [3, 4]])
    scenario.windowSystem.clearRecordedCalls()
    await scenario.command("workspace focus \(there)")
    await scenario.command("workspace focus \(back)")
    #expect(!scenario.windowSystem.nudges.isEmpty)
    #expect(scenario.harness.everyPositionIsAllowed())
  }

  @Test func aLateFrameSkipsAheadInsteadOfStretchingTheSlide() async throws {
    let scenario = await scenario(workspaces: [1: [1]])
    let start = try #require(scenario.frame(of: 1))
    scenario.windowSystem.clearRecordedCalls()
    await scenario.start("workspace focus next")
    // Moving the windows took two frames' time: the slide jumps to two thirds.
    await scenario.wait(.milliseconds(32))
    let track = Track.leaving(WindowID(1), from: start, direction: .next, on: FakeDisplays.main)
    #expect(scenario.windowSystem.nudges.map(\.origin) == [track.position(at: 2.0 / 3)])
    await scenario.wait(.milliseconds(16))
    #expect(scenario.isParked(1), "done on time")
  }

  @Test func aCommandMidSlideJumpsToTheEndFirst() async {
    let scenario = await scenario(workspaces: [1: [1, 2]])
    await scenario.start("workspace focus next")
    await scenario.wait(.milliseconds(16))
    #expect(!scenario.isParked(1), "mid-slide")

    // `list` doesn't interrupt; `retile` does, which parks the outgoing windows at once.
    await scenario.start("window list")
    #expect(!scenario.isParked(1))
    await scenario.start("workspace retile")
    #expect(scenario.isParked(1))
    #expect(scenario.isParked(2))

    // The cancelled slide must not move anything afterwards.
    let nudges = scenario.windowSystem.nudges.count
    await scenario.runUntilQuiet()
    #expect(scenario.windowSystem.nudges.count == nudges)
    #expect(scenario.isParked(1))
  }

  @Test func switchingAgainMidSlideEndsWithTheSecondTargetVisible() async {
    let scenario = await scenario(workspaces: [1: [1, 2]])
    let slots = [scenario.frame(of: 1), scenario.frame(of: 2)]
    await scenario.start("workspace focus next")
    await scenario.command("workspace focus prev")
    #expect([scenario.frame(of: 1), scenario.frame(of: 2)] == slots)
  }

  @Test func aNewWindowMidSlideFinishesTheSlideAndTiles() async {
    let scenario = await scenario(workspaces: [1: [1]])
    await scenario.start("workspace focus next")
    scenario.windowSystem.windows.append(makeWindow(id: 9))
    scenario.windowSystem.send(.created(makeWindow(id: 9)))
    await scenario.harness.settle()
    #expect(scenario.isParked(1))
    #expect(scenario.frame(of: 9) == scenario.rect(.full))
    #expect(scenario.workspaces == [1: 1, 9: 2])
  }

  @Test func aWindowFailingMidSlideDoesNotStopTheOthers() async {
    let scenario = await scenario(workspaces: [1: [1, 2]])
    scenario.windowSystem.failingMoves = [WindowID(1)]
    await scenario.command("workspace focus next")
    #expect(scenario.isParked(2))
  }
}
