import CoreGraphics
import Testing

@testable import TylerCore

private let half = WindowSize.half
private let full = WindowSize.full
private let quarter = WindowSize.quarter

@Suite("Strip layout: columns")
struct StripColumnsTests {
  @Test(arguments: [
    ([half, half, half], [[0], [1], [2]], [1, 1, 1]),
    ([quarter, quarter, half], [[0, 1], [2]], [1, 1]),
    ([quarter, half, quarter], [[0], [1], [2]], [1, 1, 1]),
    ([quarter, quarter, quarter], [[0, 1], [2]], [1, 1]),
    ([full, quarter, quarter, quarter, quarter], [[0], [1, 2], [3, 4]], [2, 1, 1]),
    ([], [], []),
  ])
  func windowsArePackedIntoColumnsInListOrder(
    sizes: [WindowSize], columns: [[Int]], widths: [Int]
  ) {
    let packed = StripColumns(sizes: sizes)
    #expect(packed.columns == columns)
    #expect(packed.widths == widths)
  }

  @Test(arguments: [
    ([half, half, half], 0, 0..<2),
    ([half, half, half], 2, 2..<3),
    ([half, full, half], 0, 0..<1),
    ([half, full, half], 1, 1..<2),
    ([full, full], 0, 0..<1),
  ])
  func theViewShowsTheWholeColumnsThatFit(sizes: [WindowSize], start: Int, visible: Range<Int>) {
    #expect(StripColumns(sizes: sizes).visible(from: start) == visible)
  }

  @Test(arguments: [
    (0, Int?(1), 0),  // already in view
    (0, 2, 1),  // one column to the right: just far enough
    (0, 3, 2),
    (2, 0, 0),  // to the left: it becomes the leftmost
    (3, 3, 2),  // the last column alone would leave empty space after it
    (0, nil, 0),
    (9, nil, 2),  // a start past the end comes back
  ])
  func scrollingShowsTheFocusedColumnWithTheLeastMovement(
    previous: Int, focused: Int?, start: Int
  ) {
    let columns = StripColumns(sizes: [half, half, half, half])
    #expect(columns.fittedStart(previous: previous, focused: focused) == start)
  }

  @Test func aFullColumnIsShownOnItsOwn() {
    let columns = StripColumns(sizes: [half, full, half])
    #expect(columns.fittedStart(previous: 0, focused: 1) == 1)
    #expect(columns.fittedStart(previous: 0, focused: 2) == 2, "the full one can't share the view")
  }

  @Test(arguments: [
    ([half, half, half, half], [0, 1, 2]),
    ([half, full, half], [0, 1, 2]),
    ([half, half], [0]),
    ([full], [0]),
    ([], []),
  ])
  func theViewCanStartAtEveryColumnThatLeavesNoSpaceAfterTheEnd(
    sizes: [WindowSize], starts: [Int]
  ) {
    #expect(StripColumns(sizes: sizes).starts == starts)
  }
}
