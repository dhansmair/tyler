import CoreGraphics
import Testing
import TylerCore

@testable import TylerServer

/// Dragging a window from the laptop (`main`: windows 1 and 2 on workspace 1) onto the Dell above
/// it (`secondary`: windows 3 and 4 on workspace 5, window 3 on the left half, 4 on the right).
@Suite("Several displays: dragging a window across")
@MainActor
struct DragAcrossDisplaysTests {
  private let dell = FakeDisplays.secondary
  private let overWindow4 = CGPoint(x: 1500, y: -700)
  private let pointer = FakePointer()

  private func onDell(_ id: UInt32) -> WindowInfo {
    makeWindow(id: id, frame: CGRect(x: 100 + CGFloat(id) * 50, y: -1000, width: 300, height: 200))
  }

  private func harness(config: Config = Config()) async -> ManagerHarness {
    let harness = ManagerHarness(
      [1, 2], extra: [onDell(3), onDell(4)],
      displays: FakeDisplays(displays: [FakeDisplays.main, FakeDisplays.secondary]),
      config: config, pointer: pointer, clock: TestClock())
    await harness.osFocus(2)
    harness.backend.clearRecordedCalls()
    return harness
  }

  /// The user picks window 2 up by its title bar and drags it over the Dell to `location`. The
  /// window keeps its size: a drag that changed it would be a resize.
  private func drag(in harness: ManagerHarness, to location: CGPoint) async {
    let size = harness.frame(of: 2)?.size ?? .zero
    pointer.isPrimaryButtonDown = true
    await harness.backend.userMoves(2, to: CGRect(origin: CGPoint(x: 1000, y: 100), size: size))
    await harness.backend.userMoves(
      2, to: CGRect(origin: CGPoint(x: location.x - 400, y: location.y - 10), size: size))
    pointer.drag(to: location)
    await harness.settle()
  }

  private func release(in harness: ManagerHarness, at location: CGPoint) async {
    pointer.release(at: location)
    await harness.settle()
  }

  @Test func nothingChangesWhileTheWindowIsStillHeld() async {
    let harness = await harness()
    let dellFrames = [harness.frame(of: 3), harness.frame(of: 4)]
    await drag(in: harness, to: overWindow4)
    #expect(harness.workspaces()[2] == 1, "still on the laptop's workspace")
    #expect([harness.frame(of: 3), harness.frame(of: 4)] == dellFrames, "no room made yet")
  }

  @Test func droppedOnAWindowItTakesThatSlotOnTheOtherDisplay() async {
    let harness = await harness()
    await drag(in: harness, to: overWindow4)
    await release(in: harness, at: overWindow4)

    #expect(harness.workspaces() == [1: 1, 2: 5, 3: 5, 4: 5])
    #expect(harness.manager.rows[1].current.windows == [3, 2, 4].map(WindowID.init))
    let dellSlots = TallLayout().frames(count: 3, in: dell.visibleFrame)
    #expect(harness.frame(of: 2) == dellSlots[1], "the dragged window snaps into its slot")
    #expect(harness.frame(of: 1) == harness.area, "the laptop re-tiles")
    #expect(harness.manager.rows.focusedKey == dell.key)
  }

  @Test func droppedOnNoWindowItGoesLast() async {
    let harness = await harness(config: Config(gaps: Config.Gaps(outer: 20)))
    let inTheGap = CGPoint(x: dell.visibleFrame.minX + 5, y: -700)
    await drag(in: harness, to: inTheGap)
    await release(in: harness, at: inTheGap)
    #expect(harness.manager.rows[1].current.windows == [3, 4, 2].map(WindowID.init))
  }

  @Test func droppedOnAnEmptyWorkspaceItFillsTheDisplay() async {
    let harness = await harness()
    _ = harness.manager.switchWorkspace(.number(6))
    await harness.osFocus(2)
    await drag(in: harness, to: overWindow4)
    await release(in: harness, at: overWindow4)
    #expect(harness.workspaces()[2] == 6)
    #expect(harness.frame(of: 2) == dell.visibleFrame)
  }

  @Test func aDragStartedWhileTheOtherDisplayHasFocusIsStillHeldAndDropped() async {
    let harness = await harness()
    // The user was working on the Dell; the laptop window's focus event hasn't arrived yet.
    await harness.osFocus(3)
    let dellFrames = [harness.frame(of: 3), harness.frame(of: 4)]
    await drag(in: harness, to: overWindow4)
    #expect(harness.workspaces()[2] == 1, "held on the laptop's workspace")
    #expect([harness.frame(of: 3), harness.frame(of: 4)] == dellFrames)

    await release(in: harness, at: overWindow4)
    #expect(harness.manager.rows[1].current.windows == [3, 2, 4].map(WindowID.init))
    #expect(harness.frame(of: 2) == TallLayout().frames(count: 3, in: dell.visibleFrame)[1])
    #expect(harness.frame(of: 1) == harness.area)
  }

  @Test func aSyncThatTakesAWindowOffAnotherDisplayLaysThatDisplayOut() async {
    let harness = await harness()
    await harness.osFocus(3)
    // Window 2 is on the Dell now, but only a switch's own sync finds out.
    let moved = makeWindow(id: 2, frame: CGRect(x: 1200, y: -800, width: 400, height: 300))
    harness.backend.windows[1] = moved
    harness.manager.registry.apply(.updated(moved))
    _ = harness.manager.switchWorkspace(.number(6))
    await harness.settle()
    #expect(harness.workspaces()[2] == 5)
    #expect(harness.frame(of: 1) == harness.area, "the laptop re-tiles around the gap")
  }
}
