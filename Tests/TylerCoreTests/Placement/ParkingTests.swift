import CoreGraphics
import Testing

@testable import TylerCore

@Suite("Parking and animation geometry")
struct ParkingTests {
  /// A display with the Dock on the left, as on the machine the limits were measured on.
  private let display = DisplayInfo(
    id: 1,
    frame: CGRect(x: 0, y: 0, width: 1800, height: 1169),
    visibleFrame: CGRect(x: 55, y: 38, width: 1745, height: 1131))

  @Test func parkedWindowsShowOnePointAtTheRightEdgeAtTheirOwnHeight() {
    let frame = Parking.frame(for: CGRect(x: 67, y: 51, width: 800, height: 600), on: display)
    #expect(frame == CGRect(x: 1799, y: 51, width: 800, height: 600))
    #expect(frame.intersection(display.visibleFrame).width == 1)
  }

  @Test func parkingUsesTheDisplaysOwnEdge() {
    let right = DisplayInfo(
      id: 2,
      frame: CGRect(x: 1800, y: -200, width: 1920, height: 1080),
      visibleFrame: CGRect(x: 1800, y: -200, width: 1920, height: 1080))
    let frame = Parking.frame(for: CGRect(x: 1900, y: 0, width: 10, height: 10), on: right)
    #expect(frame.origin == CGPoint(x: 3719, y: 0))
  }

  @Test func theAllowedPositionsKeepAPointInsideTheVisibleFrame() {
    // Measured: with the Dock on the left (visible frame from x = 55), x = -800 is accepted for
    // an 856-point window and x = -801 is pulled back; at the right edge 1799 is the limit.
    #expect(Parking.allowedX(width: 856, on: display) == -800...1799)
  }

  @Test func aDisplayThatParksOnTheLeftHidesWindowsPastItsLeftEdge() {
    var left = display
    left.parkingEdge = .left
    let frame = Parking.frame(for: CGRect(x: 67, y: 51, width: 800, height: 600), on: left)
    #expect(frame == CGRect(x: left.visibleFrame.minX - 799, y: 51, width: 800, height: 600))
    #expect(Parking.allowedX(width: 800, on: left).contains(frame.minX))
  }

  @Test(arguments: [DisplaySide.right, .left])
  func aParkedWindowIsRecognisedAndPulledBackIn(edge: DisplaySide) {
    var parking = display
    parking.parkingEdge = edge
    let frame = Parking.frame(for: CGRect(x: 67, y: 51, width: 800, height: 600), on: parking)
    // Recognised at either edge, whichever the display parks at now.
    #expect(Parking.isParked(frame, on: display))
    let pulled = Parking.pulledIn(frame, on: display)
    #expect(display.visibleFrame.contains(pulled))
    #expect(pulled.size == frame.size)
    #expect(pulled.minY == 51)
    #expect(pulled.minX == (edge == .right ? 1000 : 55))
  }

  @Test(arguments: [
    CGRect(x: 67, y: 51, width: 800, height: 600),  // on screen
    CGRect(x: 1797, y: 51, width: 800, height: 600),  // 3 points showing
    CGRect(x: 1800, y: 51, width: 800, height: 600),  // off the visible frame altogether
  ])
  func aWindowShowingMoreOrNothingIsNotParked(frame: CGRect) {
    #expect(!Parking.isParked(frame, on: display))
  }

  @Test func aWindowWiderThanTheDisplayIsPulledInToItsLeftEdge() {
    let frame = CGRect(x: 1799, y: 51, width: 2000, height: 600)
    #expect(Parking.pulledIn(frame, on: display).minX == 55)
  }

  @Test(arguments: [(0.0, 0.0), (0.5, 0.5), (1.0, 1.0), (-1.0, 0.0), (2.0, 1.0)])
  func easingKeepsItsEndpointsAndClamps(progress: Double, expected: Double) {
    #expect(Easing.easeInOut(progress) == expected)
  }

  @Test func easingIsSlowAtTheEndsAndMonotonic() {
    #expect(Easing.easeInOut(0.1) < 0.1)
    #expect(Easing.easeInOut(0.9) > 0.9)
    let samples = stride(from: 0.0, through: 1.0, by: 0.05).map(Easing.easeInOut)
    #expect(zip(samples, samples.dropFirst()).allSatisfy { $0 <= $1 })
  }

  @Test func tracksInterpolateAndRoundToWholePoints() {
    let track = Track(id: WindowID(1), start: CGPoint(x: 0, y: 0), end: CGPoint(x: -1001, y: 0))
    #expect(track.position(at: 0) == .zero)
    #expect(track.position(at: 1) == CGPoint(x: -1001, y: 0))
    #expect(track.position(at: 0.5) == CGPoint(x: -501, y: 0), "-500.5 rounds away from zero")
  }

  @Test func tracksStopAtTheEdgeOfTheAllowedRange() {
    let track = Track(
      id: WindowID(1), start: CGPoint(x: 0, y: 5), end: CGPoint(x: 1000, y: 5),
      allowedX: 0...300)
    #expect(track.position(at: 0.5) == CGPoint(x: 300, y: 5))
    #expect(track.position(at: 1) == CGPoint(x: 300, y: 5))
    #expect(track.position(at: 0.1).x == 4, "before the edge it moves as if unclamped")
  }

  @Test func leavingWindowsMoveByTheVisibleWidthAndStopAtTheEdge() {
    let frame = CGRect(x: 932, y: 51, width: 856, height: 549)
    let left = Track.leaving(WindowID(1), from: frame, direction: .next, on: display)
    #expect(left.end == CGPoint(x: 932 - 1745, y: 51))
    #expect(left.position(at: 1) == CGPoint(x: -800, y: 51))
    let right = Track.leaving(WindowID(1), from: frame, direction: .prev, on: display)
    #expect(right.position(at: 1) == CGPoint(x: 1799, y: 51))
  }

  @Test func enteringWindowsStartAtTheEdgeOnTheOtherSide() {
    let slot = CGRect(x: 67, y: 51, width: 856, height: 1106)
    let fromRight = Track.entering(WindowID(1), into: slot, direction: .next, on: display)
    #expect(fromRight.position(at: 0) == CGPoint(x: 1799, y: 51))
    #expect(fromRight.position(at: 1) == slot.origin)
    let fromLeft = Track.entering(WindowID(1), into: slot, direction: .prev, on: display)
    #expect(fromLeft.position(at: 0) == CGPoint(x: -800, y: 51))
  }

  @Test func outgoingWindowsLeaveLeftwardsWhenScrollingDown() {
    #expect(ScrollDirection.next.outgoingOffset(width: 1000) == -1000)
    #expect(ScrollDirection.prev.outgoingOffset(width: 1000) == 1000)
    #expect(ScrollDirection.next.opposite == .prev)
    #expect(ScrollDirection.prev.opposite == .next)
  }
}
