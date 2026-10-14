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

  @Test(arguments: [
    ([DisplaySide.right], ScrollDirection.next), ([.right], .prev), ([.left], .next),
    ([.left, .right], .prev),
  ])
  func besideANeighbourEveryWindowJumps(neighbours: [DisplaySide], direction: ScrollDirection) {
    var beside = display
    beside.neighbours = Set(neighbours)
    beside.parkingEdge = neighbours == [.right] ? .left : .right
    let plan = SlidePlan(
      to: 1, direction: direction, leaving: [current], entering: [slot], on: beside)
    let parked = Placement(id: WindowID(1), frame: Parking.frame(for: current.frame, on: beside))
    #expect(plan.tracks.isEmpty)
    #expect(plan.start == [parked, slot], "straight to the parking spot and into the slot")
    #expect(plan.finals == [parked, slot])
    #expect(plan.windows == [WindowID(1), WindowID(2)])
  }

  @Test(arguments: [ScrollDirection.next, .prev])
  func everyWindowHasOneTrack(direction: ScrollDirection) {
    #expect(plan(direction).tracks.map(\.id) == [WindowID(1), WindowID(2)])
    #expect(plan(direction).target == 1)
  }
}
