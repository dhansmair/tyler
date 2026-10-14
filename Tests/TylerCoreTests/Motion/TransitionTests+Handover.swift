import CoreGraphics
import Testing

@testable import TylerCore

/// A preview moving window 1 from the left half to the right half of 1000 × 600 is a third of the
/// way when window 2 takes over the right half and window 1 is sent back.
@Suite("Transition: handing over")
struct TransitionHandoverTests {
  private static let left = CGRect(x: 0, y: 0, width: 500, height: 600)
  private static let right = CGRect(x: 500, y: 0, width: 500, height: 600)
  private static let upper = CGRect(x: 500, y: 0, width: 500, height: 300)
  private static let partWay = CGRect(x: 160, y: 0, width: 500, height: 600)

  private static let frames: [WindowID: CGRect] = [WindowID(1): partWay, WindowID(2): upper]

  @Test func eachWindowGoesOnFromWhereItIs() {
    let transition = Transition(
      handingOver: [Placement(id: WindowID(1), frame: Self.right)],
      to: [
        Placement(id: WindowID(1), frame: Self.left), Placement(id: WindowID(2), frame: Self.right),
      ],
      from: { Self.frames[$0] }, duration: .milliseconds(100))
    #expect(transition.tracks.map(\.id) == [WindowID(1), WindowID(2)])
    #expect(transition.tracks[0].start == Self.partWay.origin)
    #expect(transition.tracks[0].end == Self.left.origin)
    #expect(
      transition.startFrames == [WindowID(1): Self.partWay, WindowID(2): Self.upper])
  }

  @Test func aWindowTheNewPlacementsLeaveOutGoesOnToWhereItWasGoing() {
    let transition = Transition(
      handingOver: [Placement(id: WindowID(1), frame: Self.right)],
      to: [Placement(id: WindowID(2), frame: Self.left)],
      from: { Self.frames[$0] }, duration: .milliseconds(100))
    #expect(
      transition.finals == [
        Placement(id: WindowID(1), frame: Self.right), Placement(id: WindowID(2), frame: Self.left),
      ])
  }

  @Test func aWindowAlreadyThereTakesNoPart() {
    let transition = Transition(
      handingOver: [], to: [Placement(id: WindowID(2), frame: Self.upper)],
      from: { Self.frames[$0] }, duration: .milliseconds(100))
    #expect(transition.tracks.isEmpty)
    #expect(transition.finals.isEmpty)
  }
}
