import CoreGraphics
import Testing
import TylerConfig
import TylerCore
import TylerTestSupport

@testable import TylerServer

/// The drag preview moving windows over `animations.drag-preview` (48 ms here: two steps, then
/// the final placement). The windows tile as in `MoveByDragScenarios`; window 3 dragged over the
/// upper half of the master's slot would join the master section above window 1.
@Suite("Move by drag: animated preview")
@MainActor
struct DragPreviewAnimationScenarios {
  private let main = CGRect(x: 55, y: 38, width: 873, height: 1131)
  private let upper = CGRect(x: 928, y: 38, width: 872, height: 566)
  private let lower = CGRect(x: 928, y: 604, width: 872, height: 565)
  private let mainLower = CGRect(x: 55, y: 604, width: 873, height: 565)
  private let stackAlone = CGRect(x: 928, y: 38, width: 872, height: 1131)

  private let overMain = CGPoint(x: 300, y: 500)
  private let overUpper = CGPoint(x: 1300, y: 300)
  private let outside = CGPoint(x: 10, y: 10)

  private let pointer = FakePointer()
  private let clock = TestClock()
  private let harness: ManagerHarness
  private var windowSystem: FakeWindowSystem { harness.windowSystem }

  init() async {
    var config = Config()
    config.animations.dragPreview = 48
    harness = ManagerHarness(
      [1, 2, 3], animator: Animator(frameInterval: .milliseconds(16), clock: clock),
      config: config, pointer: pointer, clock: clock)
    await harness.settle()
    windowSystem.clearRecordedCalls()
  }

  /// The user drags window 3 by its title bar: the app moves it, keeping its size.
  private func pickUpLowerWindow() async {
    pointer.isPrimaryButtonDown = true
    await windowSystem.userMoves(3, to: CGRect(x: 600, y: 300, width: 872, height: 565))
  }

  private func dragPointer(to location: CGPoint) async {
    pointer.drag(to: location)
    await harness.settle()
  }

  private func release(at location: CGPoint) async {
    pointer.release(at: location)
    await harness.settle()
  }

  private func advanceOneFrame() async {
    clock.advance(by: .milliseconds(16))
    await harness.settle()
  }

  private func runAnimations() async {
    await harness.settle()
    while clock.hasSleepers { await advanceOneFrame() }
  }

  private func steps(of id: UInt32) -> [CGRect] {
    windowSystem.frameSteps.filter { $0.id == WindowID(id) }.map(\.frame)
  }

  @Test func theWindowsMakeRoomStepByStep() async {
    await pickUpLowerWindow()
    await dragPointer(to: overMain)
    #expect(windowSystem.moves.isEmpty, "nothing jumps")

    await runAnimations()
    #expect(steps(of: 1).count == 2)
    #expect(steps(of: 1).allSatisfy { main.minY < $0.minY && $0.minY < mainLower.minY })
    #expect(windowSystem.frame(of: 1) == mainLower)
  }

  /// Every move of the pointer asks for the preview again; over the same window, the one under
  /// way goes on.
  @Test func movingThePointerOverTheSameTargetLetsThePreviewGoOn() async {
    await pickUpLowerWindow()
    await dragPointer(to: overMain)
    await advanceOneFrame()
    await dragPointer(to: CGPoint(x: 400, y: 450))
    await advanceOneFrame()
    await dragPointer(to: CGPoint(x: 410, y: 460))

    await runAnimations()
    #expect(steps(of: 1).count == 2, "48 ms from the first step, not from the last pointer move")
    #expect(windowSystem.frame(of: 1) == mainLower)
  }

  @Test func aNewTargetTakesOverWhereTheWindowIs() async throws {
    await pickUpLowerWindow()
    await dragPointer(to: overMain)
    await advanceOneFrame()
    let reached = try #require(steps(of: 1).last)

    await dragPointer(to: overUpper)
    await advanceOneFrame()
    let back = try #require(steps(of: 1).last)
    #expect(main.minY < back.minY && back.minY < reached.minY, "back from where it got to")

    await runAnimations()
    #expect(windowSystem.frame(of: 1) == main)
    #expect(windowSystem.frame(of: 2) == lower)
  }

  @Test func aDropDuringThePreviewPutsTheWindowsIntoTheirSlots() async {
    await pickUpLowerWindow()
    await dragPointer(to: overMain)
    await advanceOneFrame()

    await release(at: overMain)
    let stepped = windowSystem.frameSteps.count
    await runAnimations()
    #expect(windowSystem.frameSteps.count == stepped, "the preview stopped at the drop")
    #expect(harness.manager.workspaces.current.windows == [3, 1, 2].map(WindowID.init))
    #expect(windowSystem.frame(of: 3) == CGRect(x: 55, y: 38, width: 873, height: 566))
    #expect(windowSystem.frame(of: 1) == mainLower)
    #expect(windowSystem.frame(of: 2) == stackAlone)
  }

  @Test func aReleaseElsewhereDuringThePreviewPutsTheWindowBack() async {
    await pickUpLowerWindow()
    await dragPointer(to: overMain)
    await advanceOneFrame()

    await release(at: outside)
    await runAnimations()
    #expect(harness.manager.workspaces.current.windows == [1, 2, 3].map(WindowID.init))
    #expect(windowSystem.frame(of: 1) == main)
    #expect(windowSystem.frame(of: 3) == lower)
  }

  /// Window 1 is on its way back from the dragged window's slot when the drag ends.
  @Test func aReleaseWhileAnEarlierTargetGoesBackLeavesItInItsSlot() async {
    await pickUpLowerWindow()
    await dragPointer(to: overMain)
    await advanceOneFrame()
    await dragPointer(to: overUpper)
    await advanceOneFrame()

    await release(at: outside)
    await runAnimations()
    #expect(windowSystem.frame(of: 1) == main)
    #expect(windowSystem.frame(of: 2) == upper)
  }

  @Test func aCommandDuringThePreviewPutsTheWindowBack() async {
    await pickUpLowerWindow()
    await dragPointer(to: overMain)
    await advanceOneFrame()

    _ = harness.manager.retile()
    await runAnimations()
    #expect(windowSystem.frame(of: 1) == main)
  }

  @Test func aZeroDurationMovesTheWindowAtOnce() async {
    _ = harness.manager.setConfig("animations.drag-preview", to: "0")
    await pickUpLowerWindow()
    await dragPointer(to: overMain)

    #expect(
      windowSystem.moves == [
        Placement(id: WindowID(1), frame: mainLower), Placement(id: WindowID(2), frame: stackAlone),
      ])
    #expect(windowSystem.frameSteps.isEmpty)
  }
}
