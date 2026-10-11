import CoreGraphics
import Testing

@testable import TylerCore

/// Four half windows in 1000 × 600: the view can rest at windows 1, 2 and 3 (500 points apart).
@Suite("Strip layout: scrolling with the trackpad")
struct StripScrollTests {
  private static let area = CGRect(x: 0, y: 0, width: 1000, height: 600)
  private let display = DisplayInfo(id: 1, frame: Self.area, visibleFrame: Self.area)

  private func makeScroll(_ count: UInt32 = 4, from current: UInt32 = 1) -> StripScroll? {
    var workspace = Workspace(layout: .strip)
    for value in 1...count { workspace.append(WindowID(value)) }
    return StripScroll(
      views: workspace.stripViews(in: Self.area, gaps: LayoutGaps()),
      current: WindowID(current), on: display)
  }

  @Test func theViewsAreTheColumnBoundaries() throws {
    let scroll = try #require(makeScroll())
    #expect(scroll.offsets == [0, 500, 1000])
    #expect(scroll.views.map(\.firstVisible) == ids(1, 2, 3))
  }

  @Test func aStripThatFitsHasNowhereToScroll() {
    #expect(makeScroll(2) == nil)
  }

  @Test func thePanBeginsAtTheCurrentView() throws {
    #expect(try #require(makeScroll(from: 2)).startIndex == 1)
  }

  @Test(arguments: [(-0.5, CGFloat(500)), (-5, 1000), (0.3, 0), (-0.25, 250)])
  func thePositionFollowsTheContentWithinTheViews(offset: Double, position: CGFloat) throws {
    #expect(try #require(makeScroll()).position(movedBy: offset) == position)
  }

  @Test(arguments: [(CGFloat(250), 0, 0.5), (0, 0, 0), (500, 1, 0), (1000, 1, 1)])
  func aPositionLiesBetweenTwoViews(position: CGFloat, index: Int, progress: Double) throws {
    let segment = try #require(makeScroll()).segment(at: position)
    #expect(segment.index == index)
    #expect(segment.progress == progress)
  }

  @Test func theScrollBetweenTwoViewsMovesTheirWindows() throws {
    #expect(try #require(makeScroll()).plan(forSegment: 1).windows == Set(ids(2, 3, 4)))
  }

  @Test func windowsRestInTheirSlotsOrParked() throws {
    let resting = try #require(makeScroll()).resting([WindowID(1), WindowID(3)], at: 0)
    #expect(
      resting == [
        Placement(id: WindowID(1), frame: CGRect(x: 0, y: 0, width: 500, height: 600)),
        Placement(id: WindowID(3), frame: CGRect(x: 999, y: 0, width: 500, height: 600)),
      ])
  }
}
