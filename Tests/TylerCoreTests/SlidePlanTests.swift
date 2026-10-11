import CoreGraphics
import Testing

@testable import TylerCore

@Suite("SlidePlan")
struct SlidePlanTests {
  private let display = DisplayInfo(
    id: 1, frame: CGRect(x: 0, y: 0, width: 1800, height: 1169),
    visibleFrame: CGRect(x: 55, y: 38, width: 1745, height: 1131))
  private let current = Placement(
    id: WindowID(1), frame: CGRect(x: 55, y: 38, width: 800, height: 600))
  private let slot = Placement(
    id: WindowID(2), frame: CGRect(x: 55, y: 38, width: 1745, height: 1131))

  private func plan(_ direction: ScrollDirection = .next) -> SlidePlan {
    SlidePlan(to: 1, direction: direction, leaving: [current], entering: [slot], on: display)
  }

  @Test func leavingWindowsParkAndComeBackToWhereTheyWere() {
    let parked = Parking.frame(for: current.frame, on: display)
    #expect(plan().finals.first == Placement(id: WindowID(1), frame: parked))
    #expect(plan().returns.first == current)
  }

  @Test func enteringWindowsWaitParkedAtTheirSlotSizeAndEndInTheirSlot() {
    let start = plan().start.first
    #expect(start?.frame.size == slot.frame.size)
    #expect(start?.frame.origin == plan().tracks.last?.position(at: 0))
    #expect(plan().finals.last == slot)
    #expect(
      plan().returns.last
        == Placement(id: WindowID(2), frame: Parking.frame(for: slot.frame, on: display)))
  }

  /// For each case: the display's neighbours, the direction, and whether the leaving and the
  /// entering window slide (true) or jump (false).
  @Test(arguments: [
    ([DisplaySide.right], ScrollDirection.next, true, false),
    ([.right], .prev, false, true),
    ([.left], .next, false, true),
    ([.left], .prev, true, false),
    ([.left, .right], .next, false, false),
  ])
  func windowsJumpInsteadOfSlidingOntoANeighbour(
    neighbours: [DisplaySide], direction: ScrollDirection, leaves: Bool, enters: Bool
  ) {
    var beside = display
    beside.neighbours = Set(neighbours)
    beside.parkingEdge = neighbours == [.right] ? .left : .right
    let plan = SlidePlan(
      to: 1, direction: direction, leaving: [current], entering: [slot], on: beside)
    let parked = Placement(id: WindowID(1), frame: Parking.frame(for: current.frame, on: beside))
    #expect(plan.tracks.contains { $0.id == WindowID(1) } == leaves)
    #expect(plan.tracks.contains { $0.id == WindowID(2) } == enters)
    #expect(plan.start.contains(parked) == !leaves, "a leaving window jumps to its parking spot")
    #expect(plan.start.contains(slot) == !enters, "an entering window jumps into its slot")
    #expect(plan.finals == [parked, slot])
    #expect(plan.windows == [WindowID(1), WindowID(2)])
  }

  @Test(arguments: [ScrollDirection.next, .prev])
  func everyWindowHasOneTrack(direction: ScrollDirection) {
    #expect(plan(direction).tracks.map(\.id) == [WindowID(1), WindowID(2)])
    #expect(plan(direction).target == 1)
  }
}

@Suite("Directions and geometry")
struct DirectionTests {
  @Test(arguments: [(-0.5, ScrollDirection?.some(.next)), (0.5, .prev), (0, nil)])
  func anOffsetRevealsTheNeighbourOnTheOtherSide(offset: Double, side: ScrollDirection?) {
    #expect(ScrollDirection(revealedBy: offset) == side)
  }

  @Test(arguments: [
    (WorkspaceTarget.prev, 0, 3, ScrollDirection.prev),
    (.next, 3, 0, .next),
    (.number(3), 0, 2, .next),
    (.number(1), 2, 0, .prev),
  ])
  func aTargetScrollsTheRowItsWay(
    target: WorkspaceTarget, source: Int, index: Int, direction: ScrollDirection
  ) {
    #expect(target.direction(from: source, to: index) == direction)
  }

  @Test func rectsWithinAPointAreClose() {
    let rect = CGRect(x: 10, y: 10, width: 100, height: 100)
    #expect(rect.isClose(to: CGRect(x: 11, y: 9, width: 101, height: 99)))
    #expect(!rect.isClose(to: CGRect(x: 12, y: 10, width: 100, height: 100)))
  }

  @Test func onlyASizeChangeOfMoreThanAPointCounts() {
    let rect = CGRect(x: 10, y: 10, width: 100, height: 100)
    #expect(!rect.hasOtherSize(than: CGRect(x: 500, y: 500, width: 101, height: 100)))
    #expect(rect.hasOtherSize(than: CGRect(x: 10, y: 10, width: 102, height: 100)))
  }

  @Test func clampingMovesAValueIntoTheRange() {
    #expect((-0.5).clamped(to: 0...1) == 0)
    #expect(0.25.clamped(to: 0...1) == 0.25)
    #expect(7.clamped(to: 1...4) == 4)
  }

  @Test(arguments: [(0, -1, 2), (2, 1, 0), (1, 1, 2), (0, 4, 1)])
  func steppingWrapsAroundBothEnds(index: Int, offset: Int, expected: Int) {
    #expect(index.stepped(by: offset, wrappingAt: 3) == expected)
  }
}
