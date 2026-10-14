import CoreGraphics
import Testing

@testable import TylerCore

/// Two displays side by side, 1000 × 600 each, both tall: the laptop shows windows 1 (left half,
/// dragged) and 2 (right half), the external display window 4 alone.
@Suite("DragSession")
struct DragSessionTests {
  private let laptop = DisplayInfo(
    id: 1, key: DisplayKey("laptop"), frame: CGRect(x: 0, y: 0, width: 1000, height: 600),
    visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 600))
  private let external = DisplayInfo(
    id: 2, key: DisplayKey("external"), frame: CGRect(x: 1000, y: 0, width: 1000, height: 600),
    visibleFrame: CGRect(x: 1000, y: 0, width: 1000, height: 600))
  private let overWindow2 = CGPoint(x: 750, y: 300)
  private let overWindow1 = CGPoint(x: 250, y: 300)
  private let overExternal = CGPoint(x: 1500, y: 300)

  private var tiling: TilingSnapshot {
    var rows = DisplayRows(keys: [laptop.key, external.key], configured: [[1, 2], [3, 4]])
    rows[0][0].sync(eligible: ids(1, 2))
    rows[1][0].sync(eligible: ids(4))
    return TilingSnapshot(
      rows: rows, displays: DisplayArrangement.sided([laptop, external]), gaps: LayoutGaps())
  }

  private func slot(of windowID: UInt32) -> CGRect {
    tiling.slot(of: WindowID(windowID))!.frame
  }

  private let session = DragSession(windowID: WindowID(1))

  @Test func anArrivalIsOnlyOverAnotherDisplay() throws {
    #expect(session.arrival(at: overWindow2, in: tiling) == nil)
    let arrival = try #require(session.arrival(at: overExternal, in: tiling))
    #expect(arrival.position == 1)
  }

  @Test func theSwapPreviewShowsTheTargetInTheDraggedWindowsSlot() {
    var session = session
    let shown = session.previewSwap(at: overWindow2, in: tiling)
    #expect(shown == [Placement(id: WindowID(2), frame: slot(of: 1))])
    #expect(session.previewTarget == WindowID(2))
    let again = session.previewSwap(at: overWindow2, in: tiling)
    #expect(again.isEmpty, "the same target moves nothing")
    let back = session.previewSwap(at: overWindow1, in: tiling)
    #expect(back == [Placement(id: WindowID(2), frame: slot(of: 2))])
    #expect(session.previewTarget == nil)
  }

  @Test func theArrivalPreviewMakesRoomThereAndClosesUpHere() throws {
    var session = session
    let arrival = try #require(session.arrival(at: overExternal, in: tiling))
    let moves = session.preview(arrival, in: tiling)
    #expect(!moves.contains { $0.id == WindowID(1) }, "the dragged window stays under the pointer")
    let window2 = try #require(moves.first { $0.id == WindowID(2) })
    #expect(window2.frame.width == 1000, "alone on the laptop now")
    let window4 = try #require(moves.first { $0.id == WindowID(4) })
    #expect(window4.frame.width < 1000, "making room")
    let again = session.preview(arrival, in: tiling)
    #expect(again.isEmpty)
  }

  @Test func undoingAnArrivalPutsBothDisplaysBack() throws {
    var session = session
    #expect(session.undoArrival(in: tiling).isEmpty)
    let arrival = try #require(session.arrival(at: overExternal, in: tiling))
    _ = session.preview(arrival, in: tiling)
    let undone = session.undoArrival(in: tiling)
    #expect(Set(undone.map(\.id)) == Set(ids(2, 4)))
    #expect(session.arrival == nil)
  }

  @Test func aDropOverAnotherDisplayArrives() {
    #expect(
      session.drop(at: overExternal, frame: slot(of: 1), in: tiling)
        == .arrive(Arrival(position: 1, index: 1)))
  }

  @Test func aMoveDroppedOnAnotherSlotSwaps() {
    #expect(
      session.drop(at: overWindow2, frame: slot(of: 1), in: tiling)
        == .swap(position: 0, target: WindowID(2)))
    #expect(session.drop(at: overWindow1, frame: slot(of: 1), in: tiling) == .back)
  }

  @Test func aResizeDroppedMakesTheLayoutFollowItsSize() {
    var session = session
    session.isResize = true
    let wider = CGRect(x: 0, y: 0, width: 600, height: 600)
    #expect(
      session.drop(at: overWindow2, frame: wider, in: tiling) == .resize(position: 0, frame: wider))
    session.grab = ModifierGrab(
      kind: .resize, start: overWindow1, frame: slot(of: 1), edges: [], isFloated: false)
    #expect(session.drop(at: overWindow2, frame: wider, in: tiling) == .back, "followed as it went")
  }

  @Test func theSlotOfAGoneTargetIsForgotten() {
    var session = session
    _ = session.previewSwap(at: overWindow2, in: tiling)
    #expect(session.previewTargetSlot(in: tiling)?.frame == slot(of: 2))
    session.forgetPreviewTarget(WindowID(2))
    #expect(session.previewTargetSlot(in: tiling) == nil)
  }
}
