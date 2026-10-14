import CoreGraphics
import Testing

@testable import TylerCore

@Suite("GridLayout")
struct GridLayoutTests {
  private let layout = GridLayout()
  private let area = CGRect(x: 0, y: 0, width: 1200, height: 600)

  @Test(arguments: [
    (1, [1]),
    (2, [1, 1]),
    (3, [1, 2]),
    (4, [2, 2]),
    (5, [1, 2, 2]),
    (6, [2, 2, 2]),
    (7, [1, 2, 2, 2]),
    (8, [2, 2, 2, 2]),
    (9, [3, 3, 3]),
    (10, [1, 3, 3, 3]),
    (12, [3, 3, 3, 3]),
    (13, [1, 4, 4, 4]),
  ])
  func windowsFillColumnsTwoHighWithTheLeftoverFirst(count: Int, rowCounts: [Int]) {
    #expect(GridLayout.rowCounts(for: count) == rowCounts)
  }

  @Test(arguments: 1...30)
  func everyWindowHasASlotInAtMostFourColumns(count: Int) {
    let rowCounts = GridLayout.rowCounts(for: count)
    #expect(rowCounts.reduce(0, +) == count)
    #expect(rowCounts.count <= GridLayout.maximumColumns)
    #expect(rowCounts.dropFirst().allSatisfy { $0 == rowCounts.last })
    #expect(rowCounts[0] <= rowCounts.last ?? 0, "the first column holds the leftover")
  }

  @Test func noWindowsGiveNoFrames() {
    #expect(layout.frames(count: 0, in: area).isEmpty)
  }

  @Test(arguments: 1...3)
  func upToThreeWindowsLookLikeTall(count: Int) {
    #expect(layout.frames(count: count, in: area) == TallLayout().frames(count: count, in: area))
  }

  @Test func fourWindowsTakeTheCorners() {
    #expect(
      layout.frames(count: 4, in: area) == [
        CGRect(x: 0, y: 0, width: 600, height: 300),
        CGRect(x: 0, y: 300, width: 600, height: 300),
        CGRect(x: 600, y: 0, width: 600, height: 300),
        CGRect(x: 600, y: 300, width: 600, height: 300),
      ])
  }

  @Test func fiveWindowsLeaveTheFirstAloneOnTheLeft() {
    #expect(
      layout.frames(count: 5, in: area) == [
        CGRect(x: 0, y: 0, width: 400, height: 600),
        CGRect(x: 400, y: 0, width: 400, height: 300),
        CGRect(x: 400, y: 300, width: 400, height: 300),
        CGRect(x: 800, y: 0, width: 400, height: 300),
        CGRect(x: 800, y: 300, width: 400, height: 300),
      ])
  }

  @Test func gapsSeparateColumnsAndRows() {
    let result = layout.frames(
      count: 6, in: area, gaps: LayoutGaps(inner: 10, outer: 20))
    #expect(result[0].minX == 20)
    #expect(result[0].minY == 20)
    #expect(result[1].minY - result[0].maxY == 10)
    #expect(result[2].minX - result[0].maxX == 10)
    #expect(result[5].maxX == 1180)
    #expect(result[5].maxY == 580)
  }

  @Test(arguments: 1...13)
  func framesCoverTheAreaExactlyWithoutOverlap(count: Int) {
    let odd = CGRect(x: 55, y: 38, width: 1745, height: 1131)
    let result = layout.frames(count: count, in: odd)
    #expect(result.count == count)
    let covered = result.reduce(0) { $0 + $1.width * $1.height }
    #expect(covered == odd.width * odd.height)
    for (index, first) in result.enumerated() {
      #expect(odd.contains(first))
      for second in result[(index + 1)...] {
        #expect(!first.intersects(second), "\(first) overlaps \(second)")
      }
    }
  }
}
