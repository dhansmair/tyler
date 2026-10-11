import Testing

@testable import TylerCore

/// Workspace numbers are global across displays, so a row may hold, say, 5, 6 and 9.
@Suite("WorkspaceRow numbers")
struct WorkspaceRowNumberTests {
  /// A row numbered 5, 6 and 9, with window 1 on 5, 2 on 6 and 3 on 9.
  private func row() -> WorkspaceRow {
    var row = WorkspaceRow(numbers: [5, 6, 9])
    for (index, windowID) in [1, 2, 3].enumerated() {
      row[index].sync(eligible: [WindowID(UInt32(windowID))])
    }
    return row
  }

  @Test func aRowOfCountIsNumberedFromOne() {
    #expect(WorkspaceRow(count: 3).numbers == [1, 2, 3])
  }

  @Test(arguments: [
    ([9, 5, 6], [5, 6, 9]), ([5, 5, 6], [5, 6]), ([], [1]),
  ])
  func numbersAreSortedWithoutRepeatsAndNeverNone(given: [Int], numbers: [Int]) {
    let row = WorkspaceRow(numbers: given)
    #expect(row.numbers == numbers)
    #expect(row.count == numbers.count)
  }

  @Test(arguments: [
    (WorkspaceTarget.number(6), Int?.some(1)), (.number(9), 2), (.number(7), nil),
    (.number(1), nil),
    (.next, 1), (.prev, 2),
  ])
  func targetsResolveByNumber(target: WorkspaceTarget, index: Int?) {
    #expect(row().index(of: target) == index)
  }

  @Test func eachIndexHasItsNumber() {
    let row = row()
    #expect(row.indices.map(row.number(at:)) == [5, 6, 9])
    #expect(row.index(ofNumber: 9) == 2)
  }

  @Test func newNumbersKeepTheWorkspacesThatStayAndAddEmptyOnes() {
    var row = row()
    row.select(1)
    row.setNumbers([6, 7, 9])
    #expect(row.numbers == [6, 7, 9])
    #expect(row[0].windows == [WindowID(2)])
    #expect(row[1].windows.isEmpty)
    #expect(row[2].windows == [WindowID(3), WindowID(1)], "5's window moved to the last")
    #expect(row.currentIndex == 0, "workspace 6 is still current")
  }

  @Test func losingTheCurrentWorkspaceMakesTheLastOneCurrent() {
    var row = row()
    row.select(1)
    row.setNumbers([5, 9])
    #expect(row.currentIndex == 1)
    #expect(row[1].windows == [WindowID(3), WindowID(2)])
  }

  @Test func growingNumbersOnFromTheLast() {
    var row = row()
    row.setCount(5)
    #expect(row.numbers == [5, 6, 9, 10, 11])
    row.setCount(2)
    #expect(row.numbers == [5, 6])
    #expect(row[1].windows == [WindowID(2), WindowID(3)])
  }
}
