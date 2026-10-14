import CoreGraphics
import Testing
import TylerCore
import TylerTestSupport

@testable import TylerServer

@Suite("Workspaces: animation")
@MainActor
struct WorkspaceAnimationScenarios {
  /// Three frames of 16 ms: two intermediate steps, then the final placement.
  private let clock = TestClock()
  private var animator: Animator {
    Animator(duration: .milliseconds(48), frameInterval: .milliseconds(16), clock: clock)
  }

  /// Advances the clock until no animation is waiting on it.
  private func runAnimations(_ harness: ManagerHarness) async {
    await harness.settle()
    while clock.hasSleepers {
      clock.advance(by: .milliseconds(16))
      await harness.settle()
    }
  }

  @Test func theStepCountFollowsTheDurationAndZeroSnaps() {
    #expect(Animator().stepCount == 32)
    #expect(animator.stepCount == 3)
    #expect(Animator.snap.stepCount == 0)
  }

  @Test func outgoingWindowsSlideLeftThenPark() async throws {
    let harness = ManagerHarness([1, 2], animator: animator)
    await harness.settle()  // the manager learns the tiled frames
    let start = try #require(harness.frame(of: 1))
    _ = harness.manager.switchWorkspace(.next)
    #expect(harness.frame(of: 1) == start, "nothing moves before the first frame")

    await runAnimations(harness)
    let steps = harness.backend.nudges.filter { $0.id == WindowID(1) }.map(\.origin)
    #expect(steps.count == 2)
    #expect(steps.allSatisfy { $0.x < start.minX }, "going to the next workspace slides left")
    #expect(steps.allSatisfy { $0.y == start.minY }, "nothing moves vertically")
    #expect(harness.isParked(1))
    #expect(harness.isParked(2))
  }

  @Test func incomingWindowsStartWhereTheyAreParkedAndEndInTheirSlots() async {
    let harness = ManagerHarness([1, 2], animator: animator)
    await harness.osFocus(2)
    _ = harness.manager.moveToWorkspace(.next, follow: false)
    await runAnimations(harness)
    let parked = harness.frame(of: 2)
    harness.backend.clearRecordedCalls()

    _ = harness.manager.switchWorkspace(.next)
    let first = harness.backend.moves.first { $0.id == WindowID(2) }
    #expect(first?.frame.origin == parked?.origin, "resized to its slot while still parked")
    #expect(first?.frame.size == harness.area.size)
    await runAnimations(harness)
    let steps = harness.backend.nudges.filter { $0.id == WindowID(2) }.map(\.origin.x)
    #expect(steps == steps.sorted(by: >), "it comes in from the right")
    #expect(harness.frame(of: 2) == harness.area)
  }

  @Test func besideADisplayToTheRightSwitchesAreInstant() async throws {
    let displays = FakeDisplays(displays: [FakeDisplays.main, FakeDisplays.right])
    let harness = ManagerHarness([1, 2], displays: displays, animator: animator)
    await harness.osFocus(2)
    _ = harness.manager.moveToWorkspace(.next, follow: false)
    await runAnimations(harness)
    #expect(harness.backend.nudges.isEmpty, "sent off by a jump")
    #expect(harness.frame(of: 2)?.maxX == harness.area.minX + 1, "parked at the left edge")

    for direction in [WorkspaceTarget.next, .prev] {
      _ = harness.manager.switchWorkspace(direction)
      await runAnimations(harness)
    }
    #expect(harness.backend.nudges.isEmpty, "nothing slides either way")
    #expect(harness.frame(of: 1) == harness.area)
    #expect(harness.isParked(2))
  }

  @Test func scrollingUpMovesTheOtherWay() async throws {
    let harness = ManagerHarness([1], animator: animator)
    await harness.settle()  // the manager learns the tiled frames
    let start = try #require(harness.frame(of: 1))
    _ = harness.manager.switchWorkspace(.prev)
    await runAnimations(harness)
    let steps = harness.backend.nudges.map(\.origin)
    #expect(!steps.isEmpty)
    #expect(steps.allSatisfy { $0.x > start.minX })
  }

  @Test(arguments: [(WorkspaceTarget.next, true), (.prev, false)])
  func aSentWindowTravelsTowardsItsWorkspace(target: WorkspaceTarget, right: Bool) async throws {
    let harness = ManagerHarness([1, 2], animator: animator)
    await harness.settle()  // the manager learns the tiled frames
    await harness.osFocus(2)
    let start = try #require(harness.frame(of: 2))
    _ = harness.manager.moveToWorkspace(target, follow: false)
    await runAnimations(harness)
    let steps = harness.backend.nudges.filter { $0.id == WindowID(2) }.map(\.origin.x)
    #expect(!steps.isEmpty)
    #expect(steps.allSatisfy { right ? $0 > start.minX : $0 < start.minX })
    #expect(harness.isParked(2))
  }

  @Test(arguments: [WorkspaceTarget.next, .prev])
  func noWindowIsAskedForAPositionMacOSWouldPullBack(target: WorkspaceTarget) async {
    // Two workspaces with several windows each, so windows enter and leave together.
    let harness = ManagerHarness([1, 2, 3, 4], animator: animator)
    await harness.osFocus(4)
    _ = harness.manager.moveToWorkspace(target, follow: false)
    await harness.osFocus(3)
    _ = harness.manager.moveToWorkspace(target, follow: false)
    await runAnimations(harness)
    _ = harness.manager.switchWorkspace(target)
    await runAnimations(harness)
    _ = harness.manager.switchWorkspace(target == .next ? .prev : .next)
    await runAnimations(harness)
    #expect(!harness.backend.nudges.isEmpty)
    #expect(harness.everyPositionIsAllowed())
  }

  @Test func aLateFrameSkipsAheadInsteadOfStretchingTheSlide() async throws {
    let harness = ManagerHarness([1], animator: animator)
    await harness.settle()  // the manager learns the tiled frames
    let start = try #require(harness.frame(of: 1))
    _ = harness.manager.switchWorkspace(.next)
    await harness.settle()
    // Moving the windows took two frames' time: the slide jumps to two thirds.
    clock.advance(by: .milliseconds(32))
    await harness.settle()
    let track = Track.leaving(WindowID(1), from: start, direction: .next, on: harness.display)
    #expect(harness.backend.nudges.map(\.origin) == [track.position(at: 2.0 / 3)])
    clock.advance(by: .milliseconds(16))
    await harness.settle()
    #expect(harness.isParked(1), "done on time")
  }

  @Test func aCommandMidSlideJumpsToTheEndFirst() async {
    let harness = ManagerHarness([1, 2], animator: animator)
    _ = harness.manager.switchWorkspace(.next)
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
    let harness = ManagerHarness([1, 2], animator: animator)
    let slots = [harness.frame(of: 1), harness.frame(of: 2)]
    _ = harness.manager.switchWorkspace(.next)
    _ = harness.manager.switchWorkspace(.prev)
    await runAnimations(harness)
    #expect([harness.frame(of: 1), harness.frame(of: 2)] == slots)
  }

  @Test func aNewWindowMidSlideFinishesTheSlideAndTiles() async {
    let harness = ManagerHarness([1], animator: animator)
    _ = harness.manager.switchWorkspace(.next)
    harness.backend.windows.append(makeWindow(id: 9))
    harness.backend.send(.created(makeWindow(id: 9)))
    await harness.settle()
    #expect(harness.isParked(1))
    #expect(harness.frame(of: 9) == harness.area)
    #expect(harness.workspaces() == [1: 1, 9: 2])
  }

  @Test func aWindowFailingMidSlideDoesNotStopTheOthers() async {
    let harness = ManagerHarness([1, 2], animator: animator)
    harness.backend.failingMoves = [WindowID(1)]
    _ = harness.manager.switchWorkspace(.next)
    await runAnimations(harness)
    #expect(harness.isParked(2))
  }
}
