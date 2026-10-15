import CoreGraphics
import Testing
import TylerCore
import TylerTestSupport

@testable import TylerServer

/// Moving a tiled window by dragging it onto another one's slot: it goes in there and the
/// windows in between shift by one place; in `tall`, dropped on the other column, it changes
/// section. The three windows tile as in
/// `MouseResizeScenarios`: window 1 at (55, 38, 873, 1131); window 2 at (928, 38, 872, 566) above
/// window 3 at (928, 604, 872, 565).
@Suite("Move by drag")
@MainActor
struct MoveByDragScenarios {
  private let main = CGRect(x: 55, y: 38, width: 873, height: 1131)
  private let upper = CGRect(x: 928, y: 38, width: 872, height: 566)
  private let lower = CGRect(x: 928, y: 604, width: 872, height: 565)
  private let mainUpper = CGRect(x: 55, y: 38, width: 873, height: 566)
  private let mainLower = CGRect(x: 55, y: 604, width: 873, height: 565)
  private let stackAlone = CGRect(x: 928, y: 38, width: 872, height: 1131)

  private let overMain = CGPoint(x: 300, y: 500)
  private let overUpper = CGPoint(x: 1300, y: 300)
  private let overLower = CGPoint(x: 1300, y: 900)
  private let outside = CGPoint(x: 10, y: 10)

  private let pointer = FakePointer()
  private let windowSystem: FakeWindowSystem
  // Held here because the manager's event pumps only keep it weakly.
  private let manager: WindowManager

  init() async {
    let harness = ManagerHarness([1, 2, 3], pointer: pointer, clock: TestClock())
    (manager, windowSystem) = (harness.manager, harness.windowSystem)
    await settle()
    windowSystem.clearRecordedCalls()
  }

  /// The user drags window 3 by its title bar: the app moves it, keeping its size, and reports it.
  private func pickUpLowerWindow() async {
    pointer.isPrimaryButtonDown = true
    await moveWindow(3, to: CGRect(x: 600, y: 300, width: 872, height: 565))
  }

  private func moveWindow(_ id: UInt32, to frame: CGRect) async {
    await windowSystem.userMoves(id, to: frame)
  }

  private func dragPointer(to location: CGPoint) async {
    pointer.drag(to: location)
    await settle()
  }

  private func release(at location: CGPoint) async {
    pointer.release(at: location)
    await settle()
  }

  private func frame(of id: UInt32) -> CGRect? { windowSystem.frame(of: id) }

  private var order: [UInt32] {
    manager.workspaces.current.windows.map(\.rawValue)
  }

  // MARK: - Preview

  @Test func theMainSectionMakesRoomForAStackedWindow() async {
    await pickUpLowerWindow()
    await dragPointer(to: overMain)

    #expect(
      windowSystem.moves == [
        Placement(id: WindowID(1), frame: mainLower),
        Placement(id: WindowID(2), frame: stackAlone),
      ])
    #expect(order == [1, 2, 3], "nothing moves in the list before the release")
  }

  @Test func eachStepOverTheSameWindowMovesNothingMore() async {
    await pickUpLowerWindow()
    await dragPointer(to: overMain)
    await dragPointer(to: CGPoint(x: 400, y: 450))

    #expect(windowSystem.moves.count == 2)
  }

  @Test func movingOnToAnotherWindowPutsTheFirstOneBack() async {
    await pickUpLowerWindow()
    await dragPointer(to: overMain)
    await dragPointer(to: overUpper)

    #expect(frame(of: 1) == main)
    #expect(frame(of: 2) == lower)
  }

  @Test(arguments: [CGPoint(x: 1300, y: 900), CGPoint(x: 10, y: 10)])
  func leavingTheTargetForNoTargetPutsItBack(location: CGPoint) async {
    await pickUpLowerWindow()
    await dragPointer(to: overMain)
    await dragPointer(to: location)

    #expect(frame(of: 1) == main)
  }

  // MARK: - Release

  @Test func releasingOverTheMainColumnPutsItInTheMainSection() async {
    await pickUpLowerWindow()
    await dragPointer(to: overMain)
    await release(at: overMain)

    #expect(order == [3, 1, 2])
    #expect(frame(of: 3) == mainUpper)
    #expect(frame(of: 1) == mainLower)
    #expect(frame(of: 2) == stackAlone)
  }

  @Test func theReleaseLocationDecidesEvenWithoutAPreview() async {
    await pickUpLowerWindow()
    await release(at: overUpper)

    #expect(order == [1, 3, 2])
    #expect(frame(of: 3) == upper)
    #expect(frame(of: 2) == lower)
  }

  @Test func releasingOverAnotherSlotThanThePreviewsGoesInThere() async {
    await pickUpLowerWindow()
    await dragPointer(to: overMain)
    await release(at: overUpper)

    #expect(order == [1, 3, 2])
    #expect(frame(of: 1) == main)
    #expect(frame(of: 2) == lower)
    #expect(frame(of: 3) == upper)
  }

  @Test(arguments: [CGPoint(x: 1300, y: 900), CGPoint(x: 10, y: 10)])
  func releasingOverNoTargetPutsEveryWindowBack(location: CGPoint) async {
    await pickUpLowerWindow()
    await dragPointer(to: overMain)
    await release(at: location)

    #expect(order == [1, 2, 3])
    #expect(frame(of: 1) == main)
    #expect(frame(of: 3) == lower)
  }

  @Test func theDraggedWindowKeepsFocus() async {
    windowSystem.send(.focused(WindowID(3)))
    await settle()
    await pickUpLowerWindow()
    await release(at: overMain)

    #expect(manager.workspaces.current.focused == WindowID(3))
  }

  /// A window that keeps its size (System Settings keeps its width) is narrower than its slot
  /// before the drag: moving it is still a move, not a resize.
  @Test func aWindowSmallerThanItsSlotMovesToo() async {
    let size = CGSize(width: 700, height: 471)
    windowSystem.fixedSizes[WindowID(3)] = size
    await moveWindow(3, to: CGRect(origin: lower.origin, size: size))
    windowSystem.clearRecordedCalls()

    pointer.isPrimaryButtonDown = true
    await moveWindow(3, to: CGRect(origin: CGPoint(x: 600, y: 300), size: size))
    await dragPointer(to: overMain)
    #expect(windowSystem.moves.map(\.id) == [1, 2].map(WindowID.init))

    await release(at: overMain)
    #expect(order == [3, 1, 2])
  }

  // MARK: - No move

  @Test func aResizeNeverPreviewsOrMoves() async {
    pointer.isPrimaryButtonDown = true
    // Window 3's top edge is the divider below window 2.
    await moveWindow(3, to: CGRect(x: 928, y: 504, width: 872, height: 665))
    windowSystem.clearRecordedCalls()
    await dragPointer(to: overMain)
    #expect(windowSystem.moves.isEmpty)

    await release(at: overMain)
    #expect(order == [1, 2, 3])
  }

  @Test func inFullNothingMoves() async {
    #expect(manager.setLayout(.set(.full)) == .message("layout full"))
    windowSystem.clearRecordedCalls()
    pointer.isPrimaryButtonDown = true
    await moveWindow(2, to: CGRect(x: 300, y: 200, width: 1745, height: 1131))
    await dragPointer(to: overMain)
    #expect(windowSystem.moves.isEmpty)

    await release(at: overMain)
    #expect(order == [1, 2, 3])
  }

  @Test func withoutAWindowBeingDraggedThePointerMovesNothing() async {
    await dragPointer(to: overMain)
    await release(at: overMain)

    #expect(windowSystem.moves.isEmpty)
    #expect(order == [1, 2, 3])
  }

  // MARK: - Interruptions

  @Test func aCommandDuringTheDragPutsThePreviewBack() async {
    await pickUpLowerWindow()
    await dragPointer(to: overMain)
    #expect(manager.focus(.next) == .ok)

    #expect(frame(of: 1) == main)
    #expect(frame(of: 2) == upper)
    await release(at: overMain)
    #expect(order == [1, 2, 3], "the command ended the drag")
  }

  @Test func turningTilingOffDuringTheDragPutsThePreviewBackFirst() async {
    await pickUpLowerWindow()
    await dragPointer(to: overMain)
    _ = manager.setTiling(.off)

    #expect(frame(of: 1) == main)
  }

  @Test func aPreviewedWindowThatClosesIsForgotten() async {
    await pickUpLowerWindow()
    await dragPointer(to: overMain)
    // Kept in the fake so that a move of it would succeed and show up.
    windowSystem.send(.destroyed(WindowID(1)))
    await settle()
    windowSystem.clearRecordedCalls()
    await release(at: outside)

    #expect(order == [2, 3])
    #expect(!windowSystem.moves.contains { $0.id == WindowID(1) })
  }

  @Test func droppingTheMainWindowOnTheStackPutsItThere() async {
    let scenario = await Scenario(workspaces: [1: [1, 2, 3]], layout: .tall)
    await scenario.drag(1, by: CGVector(dx: 900, dy: 300))
    #expect(scenario.list(1) == [2, 1, 3])
    #expect(scenario.frame(of: 2) == scenario.rect(.leftHalf))
    #expect(scenario.frame(of: 1) == scenario.rect(.rightTop))
    #expect(scenario.frame(of: 3) == scenario.rect(.rightBottom))
  }

  /// In a grid of four, the last window dropped on the first one's slot: the first three each
  /// move one slot on, rather than the first trading places with it.
  @Test func inAGridTheWindowsInBetweenShift() async {
    let scenario = await Scenario(workspaces: [1: [1, 2, 3, 4]], layout: .grid)
    await scenario.drag(4, by: CGVector(dx: -1000, dy: -400))
    #expect(scenario.list(1) == [4, 1, 2, 3])
    #expect(scenario.frame(of: 4) == scenario.rect(.leftTop))
    #expect(scenario.frame(of: 1) == scenario.rect(.leftBottom))
    #expect(scenario.frame(of: 2) == scenario.rect(.rightTop))
    #expect(scenario.frame(of: 3) == scenario.rect(.rightBottom))
  }

  @Test func droppingAWindowOnItsOwnSlotPutsItBack() async {
    let scenario = await Scenario(workspaces: [1: [1, 2, 3]], layout: .tall)
    await scenario.drag(1, by: CGVector(dx: 100, dy: 100))
    #expect(scenario.list(1) == [1, 2, 3])
    #expect(scenario.frame(of: 1) == scenario.rect(.leftHalf))
  }
}
