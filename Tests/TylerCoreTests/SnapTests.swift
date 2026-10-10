import CoreGraphics
import Testing

@testable import TylerCore

@Suite("Snap and easing")
struct SnapTests {
  /// The workspace row: the neighbours one display width either side.
  private static let row: [CGFloat] = [-1000, 0, 1000]

  @Test(arguments: [
    (CGFloat(0), CGFloat(0)), (-400, 0), (-600, -1000), (450, 0), (900, 1000), (-1300, -1000),
  ])
  func aSlowReleaseSettlesOnTheNearestPoint(offset: CGFloat, expected: CGFloat) {
    let target = Snap.target(offset: offset, velocity: 10, points: Self.row, flickVelocity: 500)
    #expect(target == expected)
  }

  @Test(arguments: [
    (CGFloat(-100), CGFloat(-2000), CGFloat(-1000)),  // a short flick left still goes on
    (-100, 2000, 0),  // flicked back: returns
    (100, 2000, 1000),
    (-900, -2000, -1000),  // never further than the last point
    (-1200, -2000, -1000),
    (0, -2000, -1000),  // from exactly a point, the next one
  ])
  func aFlickGoesOnToTheNextPoint(offset: CGFloat, velocity: CGFloat, expected: CGFloat) {
    let target = Snap.target(
      offset: offset, velocity: velocity, points: Self.row, flickVelocity: 500)
    #expect(target == expected)
  }

  @Test func withoutPointsTheOffsetStays() {
    #expect(Snap.target(offset: 42, velocity: 0, points: [], flickVelocity: 1) == 42)
  }

  @Test(arguments: [
    (CGFloat(500), CGFloat(500)), (1500, 1100), (-1500, -1100), (0, 0),
  ])
  func resistanceOnlyActsPastTheOutermostPoints(offset: CGFloat, expected: CGFloat) {
    #expect(Snap.resisted(offset, within: Self.row) == expected)
  }

  @Test func aSinglePointResistsBothWays() {
    #expect(Snap.resisted(100, within: [0]) == 20)
    #expect(Snap.resisted(-100, within: [0]) == -20)
  }

  @Test(arguments: [(-0.5, 0.0), (0.0, 0.0), (0.3, 0.3), (1.0, 1.0), (1.5, 1.0)])
  func linearClamps(progress: Double, expected: Double) {
    #expect(Easing.linear(progress) == expected)
  }

  @Test func easeOutStartsFastAndEndsAtOne() {
    #expect(Easing.easeOut(0) == 0)
    #expect(Easing.easeOut(1) == 1)
    #expect(Easing.easeOut(0.25) > 0.5, "most of the way in the first quarter")
    #expect(Easing.easeOut(2) == 1)
  }

  @Test func aLinearTrackFollowsTheProgressExactly() {
    let track = Track(id: WindowID(1), start: CGPoint(x: 0, y: 10), end: CGPoint(x: 100, y: 10))
    #expect(track.position(at: 0.3, easing: Easing.linear) == CGPoint(x: 30, y: 10))
    #expect(track.position(at: 0.3) != CGPoint(x: 30, y: 10), "the default eases")
  }
}
