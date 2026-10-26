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
  private let laptopHalves = TallLayout().frames(count: 2, in: FakeDisplays.main.visibleFrame)
  private let lowerLeft = CGPoint(x: 0, y: -700)
  private var twoMains: [CGRect] {
    TallLayout().frames(count: 3, in: external.visibleFrame, state: TallLayoutState(mainCount: 2))
  }

  private func scenario(config: Config = Config()) async -> Scenario {
    let scenario = await Scenario(
      displays: [FakeDisplays.main, FakeDisplays.secondary], workspaces: [1: [1, 2], 5: [3, 4]],
      config: config)
    await scenario.focus(2)
    scenario.windowSystem.clearRecordedCalls()
    return scenario
  }

  /// The user picks window 2 up by its title bar and drags it over the external display to
  /// `location`. The window keeps its size: a drag that changed it would be a resize.
  private func drag(in scenario: Scenario, to location: CGPoint) async {
    let size = scenario.frame(of: 2)?.size ?? .zero
    await scenario.pickUp(2, to: CGRect(origin: CGPoint(x: 1000, y: 100), size: size))
    await scenario.moveByHand(
      2, to: CGRect(origin: CGPoint(x: location.x - 400, y: location.y - 10), size: size))
    await scenario.dragPointer(to: location)
  }

  /// One slot is open at any time: the one a release would fill.
  @Test func overTheExternalDisplayItMakesRoomThereAndTheLaptopClosesUp() async {
    let scenario = await scenario()
    await drag(in: scenario, to: upperRight)
    #expect(scenario.workspaces[2] == 1, "still on the laptop's workspace")
    #expect(scenario.frame(of: 3) == externalSlots[0])
    #expect(scenario.frame(of: 4) == externalSlots[2], "the upper right is open for window 2")
    #expect(
      scenario.frame(of: 1) == scenario.rect(.full), "window 2's slot on the laptop is closed")
  }

  @Test func theOpenSlotFollowsThePointerAcrossTheExternalDisplay() async {
    let scenario = await scenario()
    await drag(in: scenario, to: upperRight)
    await scenario.dragPointer(to: lowerRight)
    #expect(scenario.frame(of: 4) == externalSlots[1], "the lower right is open now")
    // The lower half of the left column: window 2 would join the master section below window 3.
    await scenario.dragPointer(to: lowerLeft)
    #expect(scenario.frame(of: 3) == twoMains[0], "the master section makes room below it")
    #expect(scenario.frame(of: 4) == twoMains[2], "alone in the stack")
  }

  @Test func droppedOnTheMainColumnItJoinsTheMainSectionThere() async {
    let scenario = await scenario()
    await drag(in: scenario, to: lowerLeft)
    await scenario.release(at: lowerLeft)
    #expect(scenario.frame(of: 3) == twoMains[0])
    #expect(scenario.frame(of: 2) == twoMains[1])
    #expect(scenario.frame(of: 4) == twoMains[2])
  }

  @Test func backOverTheLaptopEverythingIsAsItWas() async {
    let scenario = await scenario()
    let frames = [1, 3, 4].map { scenario.frame(of: $0) }
    let overItsOwnSlot = CGPoint(x: 1300, y: 600)
    await drag(in: scenario, to: upperRight)
    await scenario.dragPointer(to: overItsOwnSlot)
    #expect([1, 3, 4].map { scenario.frame(of: $0) } == frames)

    await scenario.release(at: overItsOwnSlot)
    #expect(scenario.workspaces == [1: 1, 2: 1, 3: 5, 4: 5])
    #expect(scenario.frame(of: 2) == laptopHalves[1])
  }

  @Test func aCommandMidDragPutsBothDisplaysBack() async {
    let scenario = await scenario()
    await drag(in: scenario, to: upperRight)
    await scenario.command("workspace focus 6")
    #expect(scenario.frame(of: 1) == laptopHalves[0])
  }

  @Test func droppedOverTheUpperRightItGoesInBeforeWindow4() async {
    let scenario = await scenario()
    await drag(in: scenario, to: upperRight)
    await scenario.release(at: upperRight)

    #expect(scenario.workspaces == [1: 1, 2: 5, 3: 5, 4: 5])
    #expect(scenario.list(5) == [3, 2, 4])
    #expect(scenario.frame(of: 2) == externalSlots[1], "the dragged window snaps into its slot")
    #expect(scenario.frame(of: 1) == scenario.rect(.full), "the laptop re-tiles")
    #expect(scenario.focusedDisplay == 2)
  }

  @Test func droppedOverTheLowerRightItGoesLast() async {
    let scenario = await scenario()
    await drag(in: scenario, to: lowerRight)
    await scenario.release(at: lowerRight)
    #expect(scenario.list(5) == [3, 4, 2])
    #expect(scenario.frame(of: 2) == externalSlots[2])
    #expect(scenario.frame(of: 4) == externalSlots[1])
  }

  @Test func droppedOnNoWindowItGoesLast() async {
    let scenario = await scenario(config: Config(gaps: Config.Gaps(outer: 20)))
    let inTheGap = CGPoint(x: external.visibleFrame.minX + 5, y: -700)
    await drag(in: scenario, to: inTheGap)
    await scenario.release(at: inTheGap)
    #expect(scenario.list(5) == [3, 4, 2])
  }

  @Test func droppedOnAnEmptyWorkspaceItFillsTheDisplay() async {
    let scenario = await scenario()
    await scenario.command("workspace focus 6")
    await scenario.focus(2)
    await drag(in: scenario, to: upperRight)
    #expect(scenario.frame(of: 1) == scenario.rect(.full))
    await scenario.release(at: upperRight)
    #expect(scenario.workspaces[2] == 6)
    #expect(scenario.frame(of: 2) == external.visibleFrame)
  }

  @Test func aDragStartedWhileTheOtherDisplayHasFocusIsStillHeldAndDropped() async {
    let scenario = await scenario()
    // The user was working on the external display; the laptop window's focus event hasn't arrived
    // yet.
    await scenario.focus(3)
    await drag(in: scenario, to: upperRight)
    #expect(scenario.workspaces[2] == 1, "held on the laptop's workspace")
    #expect(scenario.frame(of: 4) == externalSlots[2], "room is made for it")

    await scenario.release(at: upperRight)
    #expect(scenario.list(5) == [3, 2, 4])
    #expect(scenario.frame(of: 2) == externalSlots[1])
    #expect(scenario.frame(of: 1) == scenario.rect(.full))
  }

  @Test func aSyncThatTakesAWindowOffAnotherDisplayLaysThatDisplayOut() async {
    let scenario = await scenario()
    await scenario.focus(3)
    // Window 2 is on the external display now, but no event says so: only a switch's own sync
    // finds out.
    let moved = makeWindow(id: 2, frame: CGRect(x: 1200, y: -800, width: 400, height: 300))
    if let index = scenario.windowSystem.windows.firstIndex(where: { $0.id == moved.id }) {
      scenario.windowSystem.windows[index] = moved
    }
    scenario.harness.manager.registry.apply(.updated(moved))
    await scenario.command("workspace focus 6")
    #expect(scenario.workspaces[2] == 5)
    #expect(scenario.frame(of: 1) == scenario.rect(.full), "the laptop re-tiles around the gap")
  }
}
