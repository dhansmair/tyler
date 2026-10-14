import CoreGraphics
import Testing

@testable import TylerCore

/// Tall in 1000 × 600: window 1 the main one on the left half, 2 and 3 stacked on the right,
/// then 1 and 2 swapped.
@Suite("Transition: retiling")
struct TransitionRetileTests {
  private static let main = CGRect(x: 0, y: 0, width: 500, height: 600)
  private static let top = CGRect(x: 500, y: 0, width: 500, height: 300)
  private static let bottom = CGRect(x: 500, y: 300, width: 500, height: 300)

  private let transition = Transition(
    retiling: [
      Placement(id: WindowID(1), frame: Self.main), Placement(id: WindowID(2), frame: Self.top),
      Placement(id: WindowID(3), frame: Self.bottom),
    ],
    to: [
      Placement(id: WindowID(2), frame: Self.main), Placement(id: WindowID(1), frame: Self.top),
      Placement(id: WindowID(3), frame: Self.bottom),
    ],
    duration: .milliseconds(150))

  @Test func onlyTheWindowsWhoseSlotChangedMove() {
    #expect(transition.tracks.map(\.id) == [WindowID(2), WindowID(1)])
    #expect(
      transition.finals == [
        Placement(id: WindowID(2), frame: Self.main), Placement(id: WindowID(1), frame: Self.top),
      ])
  }

  @Test func eachWindowGoesStraightFromItsOldSlotToItsNewOne() {
    #expect(transition.tracks[0].start == Self.top.origin)
    #expect(transition.tracks[0].end == Self.main.origin)
    #expect(transition.tracks[1].start == Self.main.origin)
    #expect(transition.tracks[1].end == Self.top.origin)
  }

  @Test func eachWindowChangesSizeAlongTheWay() {
    #expect(transition.start.isEmpty)
    #expect(transition.tracks[0].sizes == Track.Sizes(start: Self.top.size, end: Self.main.size))
    #expect(transition.tracks[1].sizes == Track.Sizes(start: Self.main.size, end: Self.top.size))
  }

  @Test func aWindowThatKeepsItsSizeOnlyMoves() {
    let left = CGRect(x: 0, y: 0, width: 500, height: 600)
    let right = CGRect(x: 500, y: 0, width: 500, height: 600)
    let swap = Transition(
      retiling: [Placement(id: WindowID(1), frame: left)],
      to: [Placement(id: WindowID(1), frame: right)], duration: .milliseconds(150))
    #expect(swap.tracks.map(\.sizes) == [nil])
  }

  @Test func itTakesTheDurationItIsGiven() {
    #expect(transition.duration == .milliseconds(150))
  }
}
