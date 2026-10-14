import CoreGraphics
import Testing

@testable import TylerCore

@Suite("Reconciler")
struct ReconcilerTests {
  private let slot = CGRect(x: 0, y: 0, width: 500, height: 600)

  @Test(arguments: [
    (CGRect(x: 0, y: 0, width: 500, height: 600), false),
    (CGRect(x: 1, y: 0, width: 499, height: 601), false),
    (CGRect(x: 2, y: 0, width: 500, height: 600), true),
    (CGRect(x: 0, y: 0, width: 520, height: 600), true),
  ])
  func onlyAWindowMoreThanAPointAwayMoves(current: CGRect, moves: Bool) {
    let desired = [Placement(id: WindowID(1), frame: slot)]
    #expect(Reconciler.moves(toward: desired, from: { _ in current }).isEmpty == !moves)
  }

  @Test func aWindowWithoutAFrameMoves() {
    let desired = [Placement(id: WindowID(1), frame: slot)]
    #expect(Reconciler.moves(toward: desired, from: { _ in nil }) == desired)
  }
}
