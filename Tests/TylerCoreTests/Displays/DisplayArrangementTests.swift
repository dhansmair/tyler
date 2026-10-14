import CoreGraphics
import Testing

@testable import TylerCore

@Suite("DisplayArrangement")
struct DisplayArrangementTests {
  /// A display with this id whose top-left corner is at `left, top`, 1000 × 800.
  private static func display(_ id: UInt32, left: CGFloat, top: CGFloat) -> DisplayInfo {
    let frame = CGRect(x: left, y: top, width: 1000, height: 800)
    return DisplayInfo(id: id, frame: frame, visibleFrame: frame)
  }

  /// Each case lists the displays as the provider gives them (the primary, id 1, first) and the
  /// ids in the order tyler numbers them.
  @Test(arguments: [
    (
      "another above the primary",
      [display(1, left: 0, top: 0), display(2, left: -397, top: -800)], [1, 2]
    ),
    (
      "another to the right", [display(1, left: 0, top: 0), display(2, left: 1000, top: 0)], [1, 2]
    ),
    (
      "another to the left", [display(1, left: 0, top: 0), display(2, left: -1000, top: 0)], [1, 2]
    ),
    (
      "the primary in the middle of three",
      [
        display(1, left: 0, top: 0), display(3, left: 1000, top: 0),
        display(2, left: -1000, top: 0),
      ], [1, 2, 3]
    ),
    (
      "two stacked to the right: the upper first",
      [
        display(1, left: 0, top: 0), display(2, left: 1000, top: 400),
        display(3, left: 1000, top: -400),
      ],
      [1, 3, 2]
    ),
    (
      "a lower one on the left before a higher one on the right",
      [
        display(1, left: 0, top: 0), display(2, left: 1000, top: -400),
        display(3, left: -1000, top: 200),
      ],
      [1, 3, 2]
    ),
    (
      "the same position: by id",
      [
        display(1, left: 0, top: 0), display(5, left: 1000, top: 0), display(4, left: 1000, top: 0),
      ], [1, 4, 5]
    ),
  ])
  func numbersThePrimaryFirstThenLeftToRightThenTopToBottom(
    _ setup: String, displays: [DisplayInfo], ids: [UInt32]
  ) {
    #expect(DisplayArrangement.ordered(displays).map(\.id) == ids, "\(setup)")
  }

  /// Each case lists the displays and, for each, its neighbours and parking edge.
  @Test(arguments: [
    (
      "another above", [display(1, left: 0, top: 0), display(2, left: -397, top: -800)],
      [([], DisplaySide.right), ([], .right)]
    ),
    (
      "side by side", [display(1, left: 0, top: 0), display(2, left: 1000, top: 0)],
      [([DisplaySide.right], DisplaySide.left), ([.left], .right)]
    ),
    (
      "another to the right, lower, still beside",
      [display(1, left: 0, top: 0), display(2, left: 1000, top: 700)],
      [([DisplaySide.right], DisplaySide.left), ([.left], .right)]
    ),
    (
      "three in a row: the middle one keeps the right edge",
      [
        display(1, left: 0, top: 0), display(2, left: -1000, top: 0),
        display(3, left: 1000, top: 0),
      ],
      [([DisplaySide.left, .right], DisplaySide.right), ([.right], .left), ([.left], .right)]
    ),
  ])
  func eachDisplayParksAtAnEdgeWithNoNeighbour(
    _ setup: String, displays: [DisplayInfo], expected: [([DisplaySide], DisplaySide)]
  ) {
    let sided = DisplayArrangement.sided(displays)
    #expect(sided.map(\.neighbours) == expected.map { Set($0.0) }, "\(setup)")
    #expect(sided.map(\.parkingEdge) == expected.map(\.1), "\(setup)")
  }

  @Test func noDisplaysAreNumberedAsNone() {
    #expect(DisplayArrangement.ordered([]).isEmpty)
  }

  @Test func aDisplayWithoutAKeyIsNamedByItsId() {
    let frame = CGRect(x: 0, y: 0, width: 10, height: 10)
    #expect(DisplayInfo(id: 3, frame: frame, visibleFrame: frame).key == DisplayKey("3"))
    let keyed = DisplayInfo(id: 3, key: DisplayKey("ABC"), frame: frame, visibleFrame: frame)
    #expect(keyed.key == DisplayKey("ABC"))
  }
}
