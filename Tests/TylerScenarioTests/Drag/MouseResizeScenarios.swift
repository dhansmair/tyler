import CoreGraphics
import Testing
import TylerConfig
import TylerCore
import TylerTestSupport

@testable import TylerServer

/// Resizing tiled windows with the mouse. Three windows in the fake display's visible frame
/// (55, 38, 1745 × 1131) tile as: window 1 at (55, 38, 873, 1131); window 2 at
/// (928, 38, 872, 566) above window 3 at (928, 604, 872, 565).
///
/// Each step waits only for what it starts, so a test can see the follow interval at work.
@Suite("Mouse resizing")
@MainActor
struct MouseResizeScenarios {
  private let main = CGRect(x: 55, y: 38, width: 873, height: 1131)
  private let upper = CGRect(x: 928, y: 38, width: 872, height: 566)
  private let lower = CGRect(x: 928, y: 604, width: 872, height: 565)

  private let scenario: Scenario
  private var windowSystem: FakeWindowSystem { scenario.windowSystem }
  private var pointer: FakePointer { scenario.pointer }

  init() async {
    scenario = await Self.makeStarted()
  }

  private static func makeStarted(
    _ ids: [UInt32] = [1, 2, 3], config: Config = Config()
  ) async -> Scenario {
    let scenario = await Scenario(workspaces: [1: ids], config: config)
    scenario.windowSystem.clearRecordedCalls()
    return scenario
  }

  /// The user drags window `id` to `frame`: the app moves it and reports the new frame.
  private func drag(_ id: UInt32, to frame: CGRect, in scenario: Scenario? = nil) async {
    await (scenario ?? self.scenario).windowSystem.userMoves(id, to: frame)
  }

  /// Unlike `Scenario.release(at:)`, this lets no time pass, so the follow interval shows.
  private func stepRelease() async {
    pointer.release()
    await scenario.harness.settle()
  }

  /// Lets the drag interval pass, and the step waiting for it run.
  private func waitOutTheInterval() async {
    await scenario.wait(.milliseconds(50))
  }

  private func frame(of id: UInt32) -> CGRect? { scenario.frame(of: id) }

  /// The windows that followed a step of the drag.
  private func moved() -> Set<UInt32> {
    Set(windowSystem.passingMoves.map(\.id.rawValue))
  }

  /// Where `tall` puts `count` windows with the master at `ratio` of the width.
  private func tall(_ count: Int, atRatio ratio: Double) -> [CGRect?] {
    TallLayout().frames(
      count: count, in: FakeDisplays.main.visibleFrame, state: TallLayoutState(mainRatio: ratio))
  }

  /// Where a retile puts windows 1 to `count`: shows the ratio the workspace keeps.
  private func retiledFrames(_ count: Int, in scenario: Scenario? = nil) async -> [CGRect?] {
    let scenario = scenario ?? self.scenario
    await scenario.command("workspace retile")
    return (1...count).map { scenario.frame(of: UInt32($0)) }
  }

  @Test func theStackFollowsTheLeftWindowsRightEdgeWhileItIsDragged() async {
    #expect(frame(of: 1) == main)

    pointer.isPrimaryButtonDown = true
    await drag(1, to: CGRect(x: 55, y: 38, width: 1047, height: 1131))

    #expect(moved() == [2, 3], "the dragged window is left to the user")
    #expect(frame(of: 2) == CGRect(x: 1102, y: 38, width: 698, height: 566))
    #expect(frame(of: 3) == CGRect(x: 1102, y: 604, width: 698, height: 565))
  }

  @Test func theWindowBelowFollowsTheDividerBetweenStackedWindows() async {
    pointer.isPrimaryButtonDown = true
    await drag(2, to: CGRect(x: 928, y: 38, width: 872, height: 700))

    #expect(moved() == [3])
    #expect(frame(of: 3) == CGRect(x: 928, y: 738, width: 872, height: 431))
  }

  @Test func theNeighboursFollowEveryStepOfTheDrag() async {
    pointer.isPrimaryButtonDown = true
    await drag(1, to: CGRect(x: 55, y: 38, width: 1047, height: 1131))
    await waitOutTheInterval()
    await drag(1, to: CGRect(x: 55, y: 38, width: 698, height: 1131))

    #expect(frame(of: 2)?.minX == 753)
    #expect(frame(of: 3)?.minX == 753)
    // Two steps, two windows each; the updates tylerd's own moves caused changed nothing.
    #expect(windowSystem.passingMoves.count == 4)
    #expect(windowSystem.moves.isEmpty, "steps move windows in passing; the release settles them")
  }

  @Test func resizesWithinTheIntervalAreFollowedOnceToTheNewestFrame() async {
    pointer.isPrimaryButtonDown = true
    await drag(1, to: CGRect(x: 55, y: 38, width: 1047, height: 1131))
    await drag(1, to: CGRect(x: 55, y: 38, width: 900, height: 1131))
    await drag(1, to: CGRect(x: 55, y: 38, width: 698, height: 1131))
    #expect(windowSystem.passingMoves.count == 2, "only the first resize so far")
    #expect(frame(of: 2)?.minX == 1102)

    await waitOutTheInterval()
    #expect(windowSystem.passingMoves.count == 4, "900 was skipped")
    #expect(frame(of: 2)?.minX == 753)
    #expect(frame(of: 3)?.minX == 753)
  }

  @Test func afterAQuietIntervalTheNextResizeIsFollowedAtOnce() async {
    pointer.isPrimaryButtonDown = true
    await drag(1, to: CGRect(x: 55, y: 38, width: 1047, height: 1131))
    await waitOutTheInterval()
    await waitOutTheInterval()
    windowSystem.clearRecordedCalls()

    await drag(1, to: CGRect(x: 55, y: 38, width: 698, height: 1131))
    #expect(moved() == [2, 3])
    #expect(frame(of: 2)?.minX == 753)
  }

  @Test func theIntervalStaysFreeAfterASlowStep() async {
    pointer.isPrimaryButtonDown = true
    windowSystem.onWrite = { [clock = scenario.clock] in clock.advance(by: .milliseconds(20)) }
    await drag(1, to: CGRect(x: 55, y: 38, width: 1047, height: 1131))
    windowSystem.onWrite = nil
    await drag(1, to: CGRect(x: 55, y: 38, width: 698, height: 1131))

    await scenario.wait(.milliseconds(10))
    #expect(
      windowSystem.passingMoves.count == 2, "the first step took 40 ms; the interval follows it")
    await scenario.wait(.milliseconds(40))
    #expect(windowSystem.passingMoves.count == 4)
  }

  @Test func theIntervalComesFromTheConfig() async {
    let scenario = await Self.makeStarted(
      config: Config(mouse: Config.Mouse(followInterval: 100)))
    scenario.pointer.isPrimaryButtonDown = true
    for width in [1047, 698] {
      await drag(1, to: CGRect(x: 55, y: 38, width: width, height: 1131), in: scenario)
    }

    await scenario.wait(.milliseconds(50))
    #expect(scenario.windowSystem.passingMoves.count == 2, "100 ms haven't passed yet")
    await scenario.wait(.milliseconds(50))
    #expect(scenario.windowSystem.passingMoves.count == 4)
    #expect(await retiledFrames(3, in: scenario) == tall(3, atRatio: 0.4))
  }

  @Test func anIntervalOfZeroFollowsEveryResize() async {
    let scenario = await Self.makeStarted(config: Config(mouse: Config.Mouse(followInterval: 0)))
    scenario.pointer.isPrimaryButtonDown = true
    for width in [1047, 900, 698] {
      await drag(1, to: CGRect(x: 55, y: 38, width: width, height: 1131), in: scenario)
    }

    #expect(scenario.windowSystem.passingMoves.count == 6, "two neighbours, three resizes")
    #expect(await retiledFrames(3, in: scenario) == tall(3, atRatio: 0.4))
  }

  @Test func theReleaseFollowsAResizeStillWaitingForTheInterval() async {
    pointer.isPrimaryButtonDown = true
    await drag(1, to: CGRect(x: 55, y: 38, width: 1047, height: 1131))
    await drag(1, to: CGRect(x: 55, y: 38, width: 1222, height: 1131))
    await stepRelease()
    #expect(frame(of: 2)?.minX == 1277)
    let moves = windowSystem.passingMoves.count

    await waitOutTheInterval()
    #expect(
      windowSystem.passingMoves.count == moves, "nothing is left waiting once the drag is over")
  }

  @Test func theDraggedWindowSnapsIntoItsSlotOnRelease() async {
    pointer.isPrimaryButtonDown = true
    // The right edge is a divider; the top edge is the display's and can't move.
    await drag(1, to: CGRect(x: 55, y: 100, width: 1047, height: 1069))
    windowSystem.clearRecordedCalls()
    await stepRelease()

    #expect(
      windowSystem.moves == [
        Placement(id: WindowID(1), frame: CGRect(x: 55, y: 38, width: 1047, height: 1131))
      ])
  }

  @Test func aWindowMovedByItsTitleBarGoesBackOnRelease() async {
    pointer.isPrimaryButtonDown = true
    await drag(2, to: CGRect(x: 600, y: 300, width: 872, height: 566))
    #expect(windowSystem.passingMoves.isEmpty, "nothing follows a move")

    await stepRelease()
    #expect(windowSystem.moves == [Placement(id: WindowID(2), frame: upper)])
    #expect(frame(of: 1) == main)
    #expect(frame(of: 3) == lower)
  }

  @Test func theLastSizeBeforeTheReleaseCounts() async {
    pointer.isPrimaryButtonDown = true
    await drag(1, to: CGRect(x: 55, y: 38, width: 1047, height: 1131))
    // The app reports its last size only after the button is up.
    pointer.isPrimaryButtonDown = false
    await drag(1, to: CGRect(x: 55, y: 38, width: 1222, height: 1131))
    await stepRelease()

    #expect(frame(of: 2)?.minX == 1277)
    #expect(await retiledFrames(3) == tall(3, atRatio: 0.7))
  }

  @Test func theGridFollowsAColumnEdge() async {
    let scenario = await Self.makeStarted([1, 2, 3, 4])
    await scenario.command("layout set grid")
    // The corners: windows 1 and 2 in the left column, 873 wide, 3 and 4 in the right.
    #expect(scenario.frame(of: 3)?.minX == 928)

    scenario.pointer.isPrimaryButtonDown = true
    await drag(1, to: CGRect(x: 55, y: 38, width: 1047, height: 566), in: scenario)
    scenario.pointer.release()
    await scenario.harness.settle()

    #expect(scenario.frame(of: 2)?.width == 1047)
    #expect(scenario.frame(of: 3)?.minX == 1102)
    await scenario.command("layout set tall")
    #expect(
      await retiledFrames(4, in: scenario) == tall(4, atRatio: 0.5), "tall's ratio is its own")
  }

  @Test func resizingWithoutTheButtonDownChangesNothing() async {
    await drag(1, to: CGRect(x: 55, y: 38, width: 1047, height: 1131))
    await stepRelease()

    #expect(windowSystem.moves.isEmpty && windowSystem.passingMoves.isEmpty)
  }

  // A Scenario always has pointer input.
  @Test func withoutPointerInputNothingFollowsTheMouse() async {
    let harness = ManagerHarness([1, 2, 3])
    let window = makeWindow(id: 1, frame: CGRect(x: 55, y: 38, width: 1047, height: 1131))
    harness.windowSystem.windows[0] = window
    harness.windowSystem.send(.updated(window))
    await settle()

    #expect(harness.windowSystem.moves.isEmpty && harness.windowSystem.passingMoves.isEmpty)
    #expect(harness.manager.workspaces.current.layoutStates.tall.mainRatio == 0.5)
  }

  @Test func withTilingOffNothingFollowsTheMouse() async {
    await scenario.command("tiling off")
    windowSystem.clearRecordedCalls()

    pointer.isPrimaryButtonDown = true
    await drag(1, to: CGRect(x: 55, y: 38, width: 1047, height: 1131))
    await stepRelease()

    #expect(windowSystem.moves.isEmpty && windowSystem.passingMoves.isEmpty)
  }

  @Test func aFloatedWindowIsNotFollowed() async {
    await scenario.focus(3)
    #expect(await scenario.command("window float toggle") == .ok)
    windowSystem.clearRecordedCalls()

    pointer.isPrimaryButtonDown = true
    await drag(3, to: CGRect(x: 500, y: 300, width: 900, height: 700))
    await stepRelease()

    #expect(windowSystem.moves.isEmpty && windowSystem.passingMoves.isEmpty)
  }

  @Test func aCommandEndsTheDrag() async {
    pointer.isPrimaryButtonDown = true
    await drag(2, to: CGRect(x: 600, y: 300, width: 872, height: 566))
    #expect(await scenario.command("workspace retile") == .ok)
    windowSystem.clearRecordedCalls()
    // Without the command ending the drag, window 2 would still be the only one that counts.
    await drag(3, to: CGRect(x: 928, y: 504, width: 872, height: 665))

    #expect(moved() == [2])
    #expect(frame(of: 2)?.height == 466)
  }

  @Test func thePointerStartsAndStopsWithTylerd() async {
    #expect(pointer.startCount == 1)
    await scenario.stop()
    #expect(pointer.stopCount == 1)
  }
}
