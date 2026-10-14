import CoreGraphics
import Testing

@testable import TylerCore

@Suite("Track")
struct TrackTests {
  private let track = Track(
    id: WindowID(1), start: .zero, end: CGPoint(x: 100, y: 0),
    sizes: Track.Sizes(
      start: CGSize(width: 100, height: 300), end: CGSize(width: 201, height: 600)))

  @Test func theSizeGoesFromStartToEndInStepWithThePosition() {
    #expect(track.size(at: 0, easing: Easing.linear) == CGSize(width: 100, height: 300))
    #expect(track.size(at: 0.5, easing: Easing.linear) == CGSize(width: 151, height: 450))
    #expect(track.size(at: 1, easing: Easing.linear) == CGSize(width: 201, height: 600))
  }

  @Test func aWindowWithoutSizesKeepsItsOwn() {
    let move = Track(id: WindowID(1), start: .zero, end: CGPoint(x: 100, y: 0))
    #expect(move.size(at: 0.5, easing: Easing.linear) == nil)
  }
}
