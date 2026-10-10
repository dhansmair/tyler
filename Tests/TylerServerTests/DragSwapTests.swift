import CoreGraphics
import Testing
import TylerCore

@testable import TylerServer

/// Swapping tiled windows by dragging one onto another. The three windows tile as in
/// `MouseResizeTests`: window 1 at (55, 38, 873, 1131); window 2 at (928, 38, 872, 566) above
/// window 3 at (928, 604, 872, 565).
@Suite("Swap by drag")
@MainActor
struct DragSwapTests {
  private let main = CGRect(x: 55, y: 38, width: 873, height: 1131)
  private let upper = CGRect(x: 928, y: 38, width: 872, height: 566)
  private let lower = CGRect(x: 928, y: 604, width: 872, height: 565)

  private let overMain = CGPoint(x: 300, y: 500)
  private let overUpper = CGPoint(x: 1300, y: 300)
  private let overLower = CGPoint(x: 1300, y: 900)
  private let outside = CGPoint(x: 10, y: 10)

  private let pointer = FakePointer()
  private let backend: FakeBackend
  // Held here because the manager's event pumps only keep it weakly.
  private let manager: WindowManager

  init() async {
    let harness = ManagerHarness([1, 2, 3], pointer: pointer, clock: TestClock())
    (manager, backend) = (harness.manager, harness.backend)
    await settle()
    backend.clearRecordedCalls()
  }

  /// The user drags window 3 by its title bar: the app moves it, keeping its size, and reports it.
  private func pickUpLowerWindow() async {
    pointer.isPrimaryButtonDown = true
    await moveWindow(3, to: CGRect(x: 600, y: 300, width: 872, height: 565))
  }

  private func moveWindow(_ id: UInt32, to frame: CGRect) async {
    await backend.userMoves(id, to: frame)
  }

  private func dragPointer(to location: CGPoint) async {
    pointer.drag(to: location)
    await settle()
  }

  private func release(at location: CGPoint) async {
    pointer.release(at: location)
    await settle()
  }

  private func frame(of id: UInt32) -> CGRect? { backend.frame(of: id) }

  private var order: [UInt32] {
    manager.workspaces.current.windows.map(\.rawValue)
  }

  // MARK: - Preview

  @Test func theWindowUnderThePointerMovesIntoTheDraggedWindowsSlot() async {
    await pickUpLowerWindow()
    await dragPointer(to: overMain)

    #expect(backend.moves == [Placement(id: WindowID(1), frame: lower)])
    #expect(order == [1, 2, 3], "nothing is swapped before the release")
  }

  @Test func eachStepOverTheSameWindowMovesNothingMore() async {
    await pickUpLowerWindow()
    await dragPointer(to: overMain)
    await dragPointer(to: CGPoint(x: 400, y: 700))

    #expect(backend.moves.count == 1)
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

  @Test func releasingOverAnotherWindowSwapsTheTwo() async {
    await pickUpLowerWindow()
    await dragPointer(to: overMain)
    await release(at: overMain)

    #expect(order == [3, 2, 1])
    #expect(frame(of: 3) == main)
    #expect(frame(of: 1) == lower)
    #expect(frame(of: 2) == upper)
  }

  @Test func theReleaseLocationDecidesEvenWithoutAPreview() async {
    await pickUpLowerWindow()
    await release(at: overUpper)

    #expect(order == [1, 3, 2])
    #expect(frame(of: 3) == upper)
    #expect(frame(of: 2) == lower)
  }

  @Test func releasingOverAnotherTargetThanThePreviewSwapsWithThatOne() async {
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
    backend.send(.focused(WindowID(3)))
    await settle()
    await pickUpLowerWindow()
    await release(at: overMain)

    #expect(manager.workspaces.current.focused == WindowID(3))
  }

  // MARK: - No swap

  @Test func aResizeNeverPreviewsOrSwaps() async {
    pointer.isPrimaryButtonDown = true
    // Window 3's top edge is the divider below window 2.
    await moveWindow(3, to: CGRect(x: 928, y: 504, width: 872, height: 665))
    backend.clearRecordedCalls()
    await dragPointer(to: overMain)
    #expect(backend.moves.isEmpty)

    await release(at: overMain)
    #expect(order == [1, 2, 3])
  }

  @Test func inFullNothingSwaps() async {
    #expect(manager.setLayout(.set(.full)) == .message("layout full"))
    backend.clearRecordedCalls()
    pointer.isPrimaryButtonDown = true
    await moveWindow(2, to: CGRect(x: 300, y: 200, width: 1745, height: 1131))
    await dragPointer(to: overMain)
    #expect(backend.moves.isEmpty)

    await release(at: overMain)
    #expect(order == [1, 2, 3])
  }

  @Test func withoutAWindowBeingDraggedThePointerMovesNothing() async {
    await dragPointer(to: overMain)
    await release(at: overMain)

    #expect(backend.moves.isEmpty)
    #expect(order == [1, 2, 3])
  }

  // MARK: - Interruptions

  @Test func aCommandDuringTheDragPutsThePreviewBack() async {
    await pickUpLowerWindow()
    await dragPointer(to: overMain)
    #expect(manager.focus(.next) == .ok)

    #expect(frame(of: 1) == main)
    await release(at: overMain)
    #expect(order == [1, 2, 3], "the command ended the drag")
  }

  @Test func turningTilingOffDuringTheDragPutsThePreviewBackFirst() async {
    await pickUpLowerWindow()
    await dragPointer(to: overMain)
    manager.setTiling(.off)

    #expect(frame(of: 1) == main)
  }

  @Test func aPreviewTargetThatClosesIsForgotten() async {
    await pickUpLowerWindow()
    await dragPointer(to: overMain)
    // Kept in the fake so that a move of it would succeed and show up.
    backend.send(.destroyed(WindowID(1)))
    await settle()
    backend.clearRecordedCalls()
    await release(at: outside)

    #expect(order == [2, 3])
    #expect(!backend.moves.contains { $0.id == WindowID(1) })
  }
}
