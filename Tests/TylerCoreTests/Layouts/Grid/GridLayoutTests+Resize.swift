import CoreGraphics
import Testing

@testable import TylerCore

/// A grid of four windows in 1200 × 600 takes the corners, 600 × 300 each: windows 0 and 1 on
/// the left, 2 and 3 on the right.
@Suite("Resizing the grid with the mouse")
struct GridLayoutResizeTests {
  private let area = CGRect(x: 0, y: 0, width: 1200, height: 600)
  private let layout = GridLayout()

  private func resized(
    _ index: Int, to frame: CGRect, count: Int = 4,
    state: GridLayoutState = GridLayoutState()
  ) -> GridLayoutState? {
    layout.state(
      afterResizing: index, to: frame, count: count, in: area, state: state)
  }

  @Test func draggingAColumnEdgeMovesTheColumns() throws {
    let updated = try #require(resized(0, to: CGRect(x: 0, y: 0, width: 800, height: 300)))
    let frames = layout.frames(count: 4, in: area, state: updated)
    #expect(frames.map(\.width) == [800, 800, 400, 400])
    #expect(frames[2].minX == 800)
  }

  @Test func draggingARowEdgeMovesOnlyThatColumnsRows() throws {
    let updated = try #require(resized(0, to: CGRect(x: 0, y: 0, width: 600, height: 400)))
    let frames = layout.frames(count: 4, in: area, state: updated)
    #expect(frames.map(\.height) == [400, 200, 300, 300])
  }

  @Test func aMiddleColumnsRightEdgeMovesTheDividerAfterIt() throws {
    // Five windows: 400 wide columns of 1, 2 and 2 windows.
    let updated = try #require(
      resized(1, to: CGRect(x: 400, y: 0, width: 500, height: 300), count: 5))
    let frames = layout.frames(count: 5, in: area, state: updated)
    #expect(frames.map(\.minX) == [0, 400, 400, 900, 900])
  }

  @Test(arguments: [
    CGRect(x: 20, y: 0, width: 580, height: 300),  // the area's left edge
    CGRect(x: 0, y: 20, width: 600, height: 280),  // the area's top edge
    CGRect(x: 30, y: 30, width: 600, height: 300),  // moved, not resized
  ])
  func edgesThatAreNotDividersAreIgnored(frame: CGRect) {
    #expect(resized(0, to: frame) == nil)
  }
}
