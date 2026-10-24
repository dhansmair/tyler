import CoreGraphics
import Testing
import TylerConfig
import TylerCore
import TylerTestSupport

@testable import TylerServer

/// Moving and resizing windows with the modifier held. Three windows in the fake display's visible
/// frame (55, 38, 1745 × 1131) tile `tall`: window 1 at (55, 38, 873, 1131); window 2 at
/// (928, 38, 872, 566) above window 3 at (928, 604, 872, 565).
@Suite("Moving and resizing with the modifier")
@MainActor
struct ModifierDragScenarios {
  private static let main = CGRect(x: 55, y: 38, width: 873, height: 1131)
  private static let upper = CGRect(x: 928, y: 38, width: 872, height: 566)
  private static let lower = CGRect(x: 928, y: 604, width: 872, height: 565)
  private static let overWindow1 = CGPoint(x: 400, y: 300)
  private static let overWindow2 = CGPoint(x: 1300, y: 300)
  /// Where window 2 goes from `upper` when it is floated.
  private static let floated = CGRect(x: 898, y: 68, width: 872, height: 566)

  private let pointer = FakePointer()
  private let stacking = FakeStacking()
  private let clock = TestClock()

  private func makeHarness(
    config: Config = Config(), configFile: FakeConfigFile? = nil
  ) async -> ManagerHarness {
    let harness = ManagerHarness(
      [1, 2, 3], config: config, configFile: configFile, pointer: pointer, stacking: stacking,
      clock: clock)
    await harness.settle()
    harness.windowSystem.clearRecordedCalls()
    return harness
  }

  private func moved(in harness: ManagerHarness) -> Set<UInt32> {
    Set(harness.windowSystem.moves.map(\.id.rawValue))
  }

  // MARK: - What can be grabbed

  @Test func takesOverPressesWithTheConfiguredKeys() async {
    var config = Config()
    config.mouse.modifier = [.control, .option]
    let harness = await makeHarness(config: config)
    #expect(pointer.modifierKeys == [.control, .option])
    withExtendedLifetime(harness) {}
  }

  @Test func takesOverNothingWhenTurnedOff() async {
    var config = Config()
    config.mouse.modifier = []
    let harness = await makeHarness(config: config)
    #expect(pointer.modifierKeys.isEmpty)
    #expect(!pointer.wouldGrab(at: Self.overWindow1))
    withExtendedLifetime(harness) {}
  }

  @Test func reloadChangesTheKeys() async {
    let file = FakeConfigFile(.config(Config()))
    let harness = await makeHarness(configFile: file)
    var config = Config()
    config.mouse.modifier = [.command]
    file.write(.config(config))
    _ = harness.manager.reload()
    #expect(pointer.modifierKeys == [.command])
  }

  @Test func grabsAWindowInView() async {
    let harness = await makeHarness()
    #expect(pointer.wouldGrab(at: Self.overWindow1))
    #expect(pointer.wouldGrab(at: Self.overWindow2))
    withExtendedLifetime(harness) {}
  }

  @Test func grabsNothingOutsideTheVisibleFrame() async {
    let harness = await makeHarness()
    #expect(pointer.wouldGrab(at: Self.overWindow1))
    #expect(!pointer.wouldGrab(at: CGPoint(x: 400, y: 10)), "the menu bar")
    withExtendedLifetime(harness) {}
  }

  @Test func grabsNoUnknownWindowOrMenu() async {
    let harness = await makeHarness()
    stacking.overlays = [
      (StackedWindow(id: WindowID(99), layer: 0), CGRect(x: 300, y: 200, width: 200, height: 200)),
      (
        StackedWindow(id: WindowID(2), layer: 101), CGRect(x: 1200, y: 200, width: 200, height: 200)
      ),
    ]
    #expect(!pointer.wouldGrab(at: Self.overWindow1), "a window tylerd doesn't know")
    #expect(!pointer.wouldGrab(at: Self.overWindow2), "above the normal layer")
    #expect(pointer.wouldGrab(at: CGPoint(x: 1300, y: 900)), "window 3 is still grabbable")
    withExtendedLifetime(harness) {}
  }

  @Test func grabsNothingWithTilingOff() async {
    let harness = await makeHarness()
    _ = harness.manager.setTiling(.off)
    #expect(!pointer.wouldGrab(at: Self.overWindow1))
  }

  @Test func grabsNothingDuringAnotherDrag() async {
    let harness = await makeHarness()
    pointer.isPrimaryButtonDown = true
    await harness.windowSystem.userMoves(1, to: Self.main.offsetBy(dx: 30, dy: 0))
    #expect(!pointer.wouldGrab(at: Self.overWindow2))
  }

  // MARK: - Moving

  @Test func aMovedWindowFollowsThePointerAndIsFocused() async {
    let harness = await makeHarness()
    pointer.beginGrab(.move, at: Self.overWindow1)
    pointer.moveGrab(to: CGPoint(x: 450, y: 320))
    await harness.settle()
    #expect(harness.windowSystem.nudges.last?.origin == CGPoint(x: 105, y: 58))
    #expect(harness.windowSystem.focusCalls == [WindowID(1)])
  }

  @Test func aWindowDroppedOnAnotherSwapsWithIt() async {
    let harness = await makeHarness()
    pointer.beginGrab(.move, at: Self.overWindow1)
    pointer.moveGrab(to: Self.overWindow2)
    await harness.settle()
    #expect(harness.frame(of: 2) == Self.main, "the preview shows window 2 in window 1's slot")
    pointer.endGrab(at: Self.overWindow2)
    await harness.settle()
    #expect(harness.manager.slots == [2: 1, 1: 2, 3: 3])
    #expect(harness.frame(of: 1) == Self.upper)
  }

  @Test func aWindowDroppedOverItsOwnSlotGoesBack() async {
    let harness = await makeHarness()
    pointer.beginGrab(.move, at: Self.overWindow1)
    pointer.moveGrab(to: CGPoint(x: 600, y: 400))
    pointer.endGrab(at: CGPoint(x: 600, y: 400))
    await harness.settle()
    #expect(harness.manager.slots == [1: 1, 2: 2, 3: 3])
    #expect(harness.frame(of: 1) == Self.main)
  }

  @Test func pointerMovesWithinTheIntervalAreFollowedOnceToTheNewest() async {
    let harness = await makeHarness()
    pointer.beginGrab(.move, at: Self.overWindow1)
    pointer.moveGrab(to: CGPoint(x: 410, y: 300))
    await harness.settle()
    pointer.moveGrab(to: CGPoint(x: 420, y: 300))
    pointer.moveGrab(to: CGPoint(x: 430, y: 300))
    await harness.settle()
    #expect(harness.windowSystem.nudges.count == 1, "the interval since the first step isn't up")

    clock.advance(by: .milliseconds(Config.Mouse().followInterval))
    await harness.settle()
    #expect(harness.windowSystem.nudges.map(\.origin.x) == [65, 85], "420 was skipped")
  }

  @Test func theReleaseTakesAStepStillWaiting() async {
    let harness = await makeHarness()
    pointer.beginGrab(.move, at: Self.overWindow1)
    pointer.moveGrab(to: CGPoint(x: 410, y: 300))
    await harness.settle()
    pointer.moveGrab(to: CGPoint(x: 600, y: 300))
    pointer.endGrab(at: CGPoint(x: 600, y: 300))
    await harness.settle()
    #expect(harness.windowSystem.nudges.map(\.origin.x) == [65, 255])
    #expect(harness.frame(of: 1) == Self.main, "dropped over its own slot")
  }

  @Test func theWindowsOwnUpdatesStartNoResize() async {
    let harness = await makeHarness()
    pointer.isPrimaryButtonDown = true
    pointer.beginGrab(.move, at: Self.overWindow1)
    pointer.moveGrab(to: CGPoint(x: 450, y: 300))
    await harness.settle()
    // The app reports a size it chose itself, with one edge where it was.
    await harness.windowSystem.userMoves(1, to: CGRect(x: 55, y: 38, width: 800, height: 1131))
    #expect(!moved(in: harness).contains(2), "the layout didn't follow it")
  }

  // MARK: - Resizing

  /// Grabs window 1 in its upper right quarter and drags it right by each of `deltas` in turn,
  /// measured from the press.
  private func resizeWindow1(by deltas: [CGFloat], in harness: ManagerHarness) async {
    let start = CGPoint(x: 800, y: 300)
    pointer.beginGrab(.resize, at: start)
    for offset in deltas {
      pointer.moveGrab(to: CGPoint(x: start.x + offset, y: start.y))
      await harness.settle()
    }
  }

  @Test func aResizeMovesTheGrabbedEdgeAndTheLayoutFollows() async {
    let harness = await makeHarness()
    await resizeWindow1(by: [174], in: harness)
    #expect(harness.frame(of: 1) == CGRect(x: 55, y: 38, width: 1047, height: 1131))
    #expect(harness.frame(of: 2) == CGRect(x: 1102, y: 38, width: 698, height: 566))
    #expect(harness.frame(of: 3) == CGRect(x: 1102, y: 604, width: 698, height: 565))
  }

  @Test func theEndOfAResizeCatchesUpWithThePointer() async {
    let harness = await makeHarness()
    await resizeWindow1(by: [174, 100], in: harness)
    #expect(harness.frame(of: 2)?.minX == 1102, "the second step waits for the follow interval")
    pointer.endGrab(at: CGPoint(x: 900, y: 300))
    await harness.settle()
    let frame = harness.frame(of: 1)
    #expect(frame?.isClose(to: CGRect(x: 55, y: 38, width: 973, height: 1131)) == true)
    #expect(harness.frame(of: 2)?.minX == frame?.maxX)
    #expect(harness.manager.slots == [1: 1, 2: 2, 3: 3], "a resize never swaps")
  }

  /// Window 3 reaching 60 points past its slot's bottom edge, as one macOS refused to shrink
  /// does: dragging its top edge down still moves the divider above it.
  @Test func aWindowLargerThanItsSlotStillResizes() async {
    let harness = await makeHarness()
    await harness.windowSystem.userMoves(3, to: CGRect(x: 928, y: 604, width: 872, height: 625))
    let start = CGPoint(x: 1600, y: 700)
    pointer.beginGrab(.resize, at: start)
    pointer.moveGrab(to: CGPoint(x: start.x, y: start.y + 66))
    await harness.settle()
    #expect(harness.frame(of: 2) == CGRect(x: 928, y: 38, width: 872, height: 632))
    #expect(harness.frame(of: 3) == CGRect(x: 928, y: 670, width: 872, height: 499))
  }

  /// Window 3's bottom and right edges are on the display's border. Grabbed in its lower right
  /// quarter, it moves its top and left edges, the ones between windows, so it can grow.
  @Test func grabbedBesideTheDisplaysBorderTheEdgesBetweenWindowsMove() async {
    let harness = await makeHarness()
    let start = CGPoint(x: 1600, y: 1000)
    pointer.beginGrab(.resize, at: start)
    pointer.moveGrab(to: CGPoint(x: start.x - 100, y: start.y - 66))
    await harness.settle()
    #expect(harness.frame(of: 2) == CGRect(x: 828, y: 38, width: 972, height: 500))
    #expect(harness.frame(of: 3) == CGRect(x: 828, y: 538, width: 972, height: 631))
    #expect(harness.frame(of: 1) == CGRect(x: 55, y: 38, width: 773, height: 1131))
  }

  // MARK: - Floated windows

  /// Floats window 2, which moves to `floated`, in front of the others.
  private func floatWindow2(in harness: ManagerHarness) async {
    harness.windowSystem.send(.focused(WindowID(2)))
    await harness.settle()
    _ = harness.manager.setFloat(.toggle)
    await harness.settle()
    #expect(harness.frame(of: 2) == Self.floated)
    stacking.front = [2]
    harness.windowSystem.clearRecordedCalls()
  }

  @Test func aFloatedWindowMovesFreely() async {
    let harness = await makeHarness()
    await floatWindow2(in: harness)
    pointer.beginGrab(.move, at: Self.overWindow2)
    pointer.moveGrab(to: CGPoint(x: 1200, y: 350))
    pointer.endGrab(at: CGPoint(x: 1200, y: 350))
    await harness.settle()
    #expect(harness.windowSystem.nudges.last?.origin == CGPoint(x: 798, y: 118))
    #expect(harness.windowSystem.moves.isEmpty, "nothing is tiled or put back")
  }

  @Test func aFloatedWindowResizesFreely() async {
    let harness = await makeHarness()
    await floatWindow2(in: harness)
    // The lower left quarter of window 2.
    pointer.beginGrab(.resize, at: CGPoint(x: 1000, y: 500))
    pointer.moveGrab(to: CGPoint(x: 960, y: 530))
    pointer.endGrab(at: CGPoint(x: 960, y: 530))
    await harness.settle()
    #expect(harness.windowSystem.moves.map(\.id) == [WindowID(2)])
    #expect(harness.frame(of: 2) == CGRect(x: 858, y: 68, width: 912, height: 596))
  }

  @Test func aFloatedWindowsResizeIsPacedToo() async {
    let harness = await makeHarness()
    await floatWindow2(in: harness)
    pointer.beginGrab(.resize, at: CGPoint(x: 1000, y: 500))
    for left in [990, 980, 970] {
      pointer.moveGrab(to: CGPoint(x: CGFloat(left), y: 500))
      await harness.settle()
    }
    #expect(harness.windowSystem.moves.count == 1)
    clock.advance(by: .milliseconds(Config.Mouse().followInterval))
    await harness.settle()
    #expect(harness.windowSystem.moves.count == 2)
    #expect(harness.frame(of: 2)?.minX == 868)
  }
}
