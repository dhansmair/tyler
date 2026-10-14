import CoreGraphics
import Testing
import TylerConfig
import TylerCore
import TylerTestSupport

@testable import TylerServer

/// Resizing tiled windows with the mouse. Three windows in the fake display's visible frame
/// (55, 38, 1745 × 1131) tile as: window 1 at (55, 38, 873, 1131); window 2 at
/// (928, 38, 872, 566) above window 3 at (928, 604, 872, 565).
@Suite("Mouse resizing")
@MainActor
struct MouseResizeScenarios {
  private let main = CGRect(x: 55, y: 38, width: 873, height: 1131)
  private let upper = CGRect(x: 928, y: 38, width: 872, height: 566)
  private let lower = CGRect(x: 928, y: 604, width: 872, height: 565)

  private let pointer = FakePointer()
  private let clock = TestClock()
  private let backend: FakeWindowSystem
  // Held here because the manager's event pumps only keep it weakly.
  private let manager: WindowManager

  init() async {
    (manager, backend) = await Self.makeStarted(pointer: pointer, clock: clock)
  }

  private static func makeStarted(
    pointer: FakePointer?, clock: TestClock = TestClock(), config: Config = Config()
  ) async -> (WindowManager, FakeWindowSystem) {
    let harness = ManagerHarness([1, 2, 3], config: config, pointer: pointer, clock: clock)
    await settle()
    harness.backend.clearRecordedCalls()
    return (harness.manager, harness.backend)
  }

  /// The user drags window `id` to `frame`: the app moves it and reports the new frame.
  private func drag(_ id: UInt32, to frame: CGRect) async {
    await backend.userMoves(id, to: frame)
  }

  /// Lets the drag interval pass, and the step waiting for it run.
  private func waitOutTheInterval() async {
    clock.advance(by: .milliseconds(50))
    await settle()
  }

  private func frame(of id: UInt32) -> CGRect? { backend.frame(of: id) }

  /// The windows that followed a step of the drag.
  private func moved() -> Set<UInt32> {
    Set(backend.passingMoves.map(\.id.rawValue))
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
    #expect(backend.passingMoves.count == 4)
    #expect(backend.moves.isEmpty, "steps move windows in passing; the release settles them")
  }

  @Test func resizesWithinTheIntervalAreFollowedOnceToTheNewestFrame() async {
    pointer.isPrimaryButtonDown = true
    await drag(1, to: CGRect(x: 55, y: 38, width: 1047, height: 1131))
    await drag(1, to: CGRect(x: 55, y: 38, width: 900, height: 1131))
    await drag(1, to: CGRect(x: 55, y: 38, width: 698, height: 1131))
    #expect(backend.passingMoves.count == 2, "only the first resize so far")
    #expect(frame(of: 2)?.minX == 1102)

    await waitOutTheInterval()
    #expect(backend.passingMoves.count == 4, "900 was skipped")
    #expect(frame(of: 2)?.minX == 753)
    #expect(frame(of: 3)?.minX == 753)
  }

  @Test func afterAQuietIntervalTheNextResizeIsFollowedAtOnce() async {
    pointer.isPrimaryButtonDown = true
    await drag(1, to: CGRect(x: 55, y: 38, width: 1047, height: 1131))
    await waitOutTheInterval()
    await waitOutTheInterval()
    backend.clearRecordedCalls()

    await drag(1, to: CGRect(x: 55, y: 38, width: 698, height: 1131))
    #expect(moved() == [2, 3])
    #expect(frame(of: 2)?.minX == 753)
  }

  @Test func theIntervalStaysFreeAfterASlowStep() async {
    pointer.isPrimaryButtonDown = true
    backend.onWrite = { [clock] in clock.advance(by: .milliseconds(20)) }
    await drag(1, to: CGRect(x: 55, y: 38, width: 1047, height: 1131))
    backend.onWrite = nil
    await drag(1, to: CGRect(x: 55, y: 38, width: 698, height: 1131))

    clock.advance(by: .milliseconds(10))
    await settle()
    #expect(backend.passingMoves.count == 2, "the first step took 40 ms; the interval follows it")
    clock.advance(by: .milliseconds(40))
    await settle()
    #expect(backend.passingMoves.count == 4)
  }

  @Test func theIntervalComesFromTheConfig() async {
    let pointer = FakePointer()
    let clock = TestClock()
    let (manager, backend) = await Self.makeStarted(
      pointer: pointer, clock: clock, config: Config(mouse: Config.Mouse(followInterval: 100)))
    pointer.isPrimaryButtonDown = true
    for width in [1047, 698] {
      let window = makeWindow(id: 1, frame: CGRect(x: 55, y: 38, width: width, height: 1131))
      backend.windows[0] = window
      backend.send(.updated(window))
      await settle()
    }

    clock.advance(by: .milliseconds(50))
    await settle()
    #expect(backend.passingMoves.count == 2, "100 ms haven't passed yet")
    clock.advance(by: .milliseconds(50))
    await settle()
    #expect(backend.passingMoves.count == 4)
    #expect(manager.workspaces.current.layoutStates.tall.mainRatio == 0.4)
  }

  @Test func anIntervalOfZeroFollowsEveryResize() async {
    let pointer = FakePointer()
    let (manager, backend) = await Self.makeStarted(
      pointer: pointer, config: Config(mouse: Config.Mouse(followInterval: 0)))
    pointer.isPrimaryButtonDown = true
    for width in [1047, 900, 698] {
      let window = makeWindow(id: 1, frame: CGRect(x: 55, y: 38, width: width, height: 1131))
      backend.windows[0] = window
      backend.send(.updated(window))
      await settle()
    }

    #expect(backend.passingMoves.count == 6, "two neighbours, three resizes")
    #expect(manager.workspaces.current.layoutStates.tall.mainRatio == 0.4)
  }

  @Test func theReleaseFollowsAResizeStillWaitingForTheInterval() async {
    pointer.isPrimaryButtonDown = true
    await drag(1, to: CGRect(x: 55, y: 38, width: 1047, height: 1131))
    await drag(1, to: CGRect(x: 55, y: 38, width: 1222, height: 1131))
    pointer.release()
    await settle()
    #expect(frame(of: 2)?.minX == 1277)
    let moves = backend.passingMoves.count

    await waitOutTheInterval()
    #expect(backend.passingMoves.count == moves, "nothing is left waiting once the drag is over")
  }

  @Test func theDraggedWindowSnapsIntoItsSlotOnRelease() async {

    pointer.isPrimaryButtonDown = true
    // The right edge is a divider; the top edge is the display's and can't move.
    await drag(1, to: CGRect(x: 55, y: 100, width: 1047, height: 1069))
    backend.clearRecordedCalls()
    pointer.release()
    await settle()

    #expect(
      backend.moves == [
        Placement(id: WindowID(1), frame: CGRect(x: 55, y: 38, width: 1047, height: 1131))
      ])
  }

  @Test func aWindowMovedByItsTitleBarGoesBackOnRelease() async {

    pointer.isPrimaryButtonDown = true
    await drag(2, to: CGRect(x: 600, y: 300, width: 872, height: 566))
    #expect(backend.passingMoves.isEmpty, "nothing follows a move")

    pointer.release()
    await settle()
    #expect(backend.moves == [Placement(id: WindowID(2), frame: upper)])
    #expect(frame(of: 1) == main)
    #expect(frame(of: 3) == lower)
  }

  @Test func theLastSizeBeforeTheReleaseCounts() async {

    pointer.isPrimaryButtonDown = true
    await drag(1, to: CGRect(x: 55, y: 38, width: 1047, height: 1131))
    // The app reports its last size only after the button is up.
    pointer.isPrimaryButtonDown = false
    await drag(1, to: CGRect(x: 55, y: 38, width: 1222, height: 1131))
    pointer.release()
    await settle()

    #expect(frame(of: 2)?.minX == 1277)
    #expect(manager.workspaces.current.layoutStates.tall.mainRatio == 0.7)
  }

  @Test func theGridFollowsAColumnEdge() async {
    let pointer = FakePointer()
    let harness = ManagerHarness([1, 2, 3, 4], pointer: pointer, clock: clock)
    _ = harness.manager.setLayout(.set(.grid))
    await settle()
    // The corners: windows 1 and 2 in the left column, 873 wide, 3 and 4 in the right.
    #expect(harness.frame(of: 3)?.minX == 928)

    pointer.isPrimaryButtonDown = true
    await harness.backend.userMoves(1, to: CGRect(x: 55, y: 38, width: 1047, height: 566))
    pointer.release()
    await settle()

    #expect(harness.frame(of: 2)?.width == 1047)
    #expect(harness.frame(of: 3)?.minX == 1102)
    #expect(harness.manager.workspaces.current.layoutStates.tall.mainRatio == 0.5)
  }

  @Test func resizingWithoutTheButtonDownChangesNothing() async {

    await drag(1, to: CGRect(x: 55, y: 38, width: 1047, height: 1131))
    pointer.release()
    await settle()

    #expect(backend.moves.isEmpty && backend.passingMoves.isEmpty)
  }

  @Test func withoutPointerInputNothingFollowsTheMouse() async {
    let (manager, backend) = await Self.makeStarted(pointer: nil)
    let window = makeWindow(id: 1, frame: CGRect(x: 55, y: 38, width: 1047, height: 1131))
    backend.windows[0] = window
    backend.send(.updated(window))
    await settle()

    #expect(backend.moves.isEmpty && backend.passingMoves.isEmpty)
    #expect(manager.workspaces.current.layoutStates.tall.mainRatio == 0.5)
  }

  @Test func withTilingOffNothingFollowsTheMouse() async {
    _ = manager.setTiling(.off)
    backend.clearRecordedCalls()

    pointer.isPrimaryButtonDown = true
    await drag(1, to: CGRect(x: 55, y: 38, width: 1047, height: 1131))
    pointer.release()
    await settle()

    #expect(backend.moves.isEmpty && backend.passingMoves.isEmpty)
  }

  @Test func aFloatedWindowIsNotFollowed() async {
    backend.send(.focused(WindowID(3)))
    await settle()
    #expect(manager.setFloat(.toggle) == .ok)
    backend.clearRecordedCalls()

    pointer.isPrimaryButtonDown = true
    await drag(3, to: CGRect(x: 500, y: 300, width: 900, height: 700))
    pointer.release()
    await settle()

    #expect(backend.moves.isEmpty && backend.passingMoves.isEmpty)
  }

  @Test func aCommandEndsTheDrag() async {

    pointer.isPrimaryButtonDown = true
    await drag(2, to: CGRect(x: 600, y: 300, width: 872, height: 566))
    #expect(manager.retile() == .ok)
    backend.clearRecordedCalls()
    // Without the command ending the drag, window 2 would still be the only one that counts.
    await drag(3, to: CGRect(x: 928, y: 504, width: 872, height: 665))

    #expect(moved() == [2])
    #expect(frame(of: 2)?.height == 466)
  }

  @Test func thePointerStartsAndStopsWithTheManager() {
    #expect(pointer.startCount == 1)
    manager.stop()
    #expect(pointer.stopCount == 1)
  }
}
