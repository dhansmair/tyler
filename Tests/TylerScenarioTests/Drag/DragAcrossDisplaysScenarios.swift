import CoreGraphics
import Testing
import TylerConfig
import TylerCore
import TylerTestSupport

@testable import TylerServer

/// Dragging a window from the laptop (`main`: windows 1 and 2 on workspace 1) onto the external
/// display above it (`secondary`: windows 3 and 4 on workspace 5, window 3 on the left half, 4 on
/// the right). With window 2 in, the external display's right column splits at y = −705.
@Suite("Several displays: dragging a window across")
@MainActor
struct DragAcrossDisplaysScenarios {
  private let external = FakeDisplays.secondary
  /// Over window 4, in the upper half of the right column: window 2 would go in before it.
  private let upperRight = CGPoint(x: 1500, y: -1100)
  /// Over window 4, in the lower half of the right column: window 2 would go in last.
  private let lowerRight = CGPoint(x: 1500, y: -300)
  private var externalSlots: [CGRect] { TallLayout().frames(count: 3, in: external.visibleFrame) }
  private let pointer = FakePointer()

  private func onExternal(_ id: UInt32) -> WindowInfo {
    makeWindow(id: id, frame: CGRect(x: 100 + CGFloat(id) * 50, y: -1000, width: 300, height: 200))
  }

  private func harness(config: Config = Config()) async -> ManagerHarness {
    let harness = ManagerHarness(
      [1, 2], extra: [onExternal(3), onExternal(4)],
      displays: FakeDisplays(displays: [FakeDisplays.main, FakeDisplays.secondary]),
      config: config, pointer: pointer, clock: TestClock())
    await harness.osFocus(2)
    harness.windowSystem.clearRecordedCalls()
    return harness
  }

  /// The user picks window 2 up by its title bar and drags it over the external display to
  /// `location`. The window keeps its size: a drag that changed it would be a resize.
  private func drag(in harness: ManagerHarness, to location: CGPoint) async {
    let size = harness.frame(of: 2)?.size ?? .zero
    pointer.isPrimaryButtonDown = true
    await harness.windowSystem.userMoves(
      2, to: CGRect(origin: CGPoint(x: 1000, y: 100), size: size))
    await harness.windowSystem.userMoves(
      2, to: CGRect(origin: CGPoint(x: location.x - 400, y: location.y - 10), size: size))
    pointer.drag(to: location)
    await harness.settle()
  }

  private func release(in harness: ManagerHarness, at location: CGPoint) async {
    pointer.release(at: location)
    await harness.settle()
  }

  /// One slot is open at any time: the one a release would fill.
  @Test func overTheExternalDisplayItMakesRoomThereAndTheLaptopClosesUp() async {
    let harness = await harness()
    await drag(in: harness, to: upperRight)
    #expect(harness.workspaces()[2] == 1, "still on the laptop's workspace")
    #expect(harness.frame(of: 3) == externalSlots[0])
    #expect(harness.frame(of: 4) == externalSlots[2], "the upper right is open for window 2")
    #expect(harness.frame(of: 1) == harness.area, "window 2's slot on the laptop is closed")
  }

  @Test func theOpenSlotFollowsThePointerAcrossTheExternalDisplay() async {
    let harness = await harness()
    await drag(in: harness, to: upperRight)
    pointer.drag(to: lowerRight)
    await harness.settle()
    #expect(harness.frame(of: 4) == externalSlots[1], "the lower right is open now")
    pointer.drag(to: CGPoint(x: 0, y: -700))
    await harness.settle()
    #expect(harness.frame(of: 3) == externalSlots[1], "the master slot is open now")
    #expect(harness.frame(of: 4) == externalSlots[2])
  }

  @Test func backOverTheLaptopEverythingIsAsItWas() async {
    let harness = await harness()
    let frames = [1, 3, 4].map { harness.frame(of: $0) }
    await drag(in: harness, to: upperRight)
    pointer.drag(to: CGPoint(x: 1300, y: 600))  // over window 2's own slot
    await harness.settle()
    #expect([1, 3, 4].map { harness.frame(of: $0) } == frames)

    await release(in: harness, at: CGPoint(x: 1300, y: 600))
    #expect(harness.workspaces() == [1: 1, 2: 1, 3: 5, 4: 5])
    #expect(harness.frame(of: 2) == TallLayout().frames(count: 2, in: harness.area)[1])
  }

  @Test func aCommandMidDragPutsBothDisplaysBack() async {
    let harness = await harness()
    await drag(in: harness, to: upperRight)
    _ = harness.manager.switchWorkspace(.number(6))
    await harness.settle()
    #expect(harness.frame(of: 1) == TallLayout().frames(count: 2, in: harness.area)[0])
  }

  @Test func droppedOverTheUpperRightItGoesInBeforeWindow4() async {
    let harness = await harness()
    await drag(in: harness, to: upperRight)
    await release(in: harness, at: upperRight)

    #expect(harness.workspaces() == [1: 1, 2: 5, 3: 5, 4: 5])
    #expect(harness.manager.rows[1].current.windows == [3, 2, 4].map(WindowID.init))
    #expect(harness.frame(of: 2) == externalSlots[1], "the dragged window snaps into its slot")
    #expect(harness.frame(of: 1) == harness.area, "the laptop re-tiles")
    #expect(harness.manager.rows.focusedKey == external.key)
  }

  @Test func droppedOverTheLowerRightItGoesLast() async {
    let harness = await harness()
    await drag(in: harness, to: lowerRight)
    await release(in: harness, at: lowerRight)
    #expect(harness.manager.rows[1].current.windows == [3, 4, 2].map(WindowID.init))
    #expect(harness.frame(of: 2) == externalSlots[2])
    #expect(harness.frame(of: 4) == externalSlots[1])
  }

  @Test func droppedOnNoWindowItGoesLast() async {
    let harness = await harness(config: Config(gaps: Config.Gaps(outer: 20)))
    let inTheGap = CGPoint(x: external.visibleFrame.minX + 5, y: -700)
    await drag(in: harness, to: inTheGap)
    await release(in: harness, at: inTheGap)
    #expect(harness.manager.rows[1].current.windows == [3, 4, 2].map(WindowID.init))
  }

  @Test func droppedOnAnEmptyWorkspaceItFillsTheDisplay() async {
    let harness = await harness()
    _ = harness.manager.switchWorkspace(.number(6))
    await harness.osFocus(2)
    await drag(in: harness, to: upperRight)
    #expect(harness.frame(of: 1) == harness.area)
    await release(in: harness, at: upperRight)
    #expect(harness.workspaces()[2] == 6)
    #expect(harness.frame(of: 2) == external.visibleFrame)
  }

  @Test func aDragStartedWhileTheOtherDisplayHasFocusIsStillHeldAndDropped() async {
    let harness = await harness()
    // The user was working on the external display; the laptop window's focus event hasn't arrived
    // yet.
    await harness.osFocus(3)
    await drag(in: harness, to: upperRight)
    #expect(harness.workspaces()[2] == 1, "held on the laptop's workspace")
    #expect(harness.frame(of: 4) == externalSlots[2], "room is made for it")

    await release(in: harness, at: upperRight)
    #expect(harness.manager.rows[1].current.windows == [3, 2, 4].map(WindowID.init))
    #expect(harness.frame(of: 2) == externalSlots[1])
    #expect(harness.frame(of: 1) == harness.area)
  }

  @Test func aSyncThatTakesAWindowOffAnotherDisplayLaysThatDisplayOut() async {
    let harness = await harness()
    await harness.osFocus(3)
    // Window 2 is on the external display now, but only a switch's own sync finds out.
    let moved = makeWindow(id: 2, frame: CGRect(x: 1200, y: -800, width: 400, height: 300))
    harness.windowSystem.windows[1] = moved
    harness.manager.registry.apply(.updated(moved))
    _ = harness.manager.switchWorkspace(.number(6))
    await harness.settle()
    #expect(harness.workspaces()[2] == 5)
    #expect(harness.frame(of: 1) == harness.area, "the laptop re-tiles around the gap")
  }
}
