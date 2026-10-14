import Testing

@testable import TylerCore

/// Workspace numbers are global across displays, so a row may hold, say, 5, 6 and 9.
@Suite("WorkspaceRow numbers")
struct WorkspaceRowNumbersTests {
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

  @Test func insertingGoesInByNumberAndKeepsTheCurrentWorkspace() {
    var row = row()
    row.select(1)
    var arriving = Workspace()
    arriving.sync(eligible: [WindowID(7)])
    let inserted = row.insert(arriving, number: 3)
    #expect(inserted)
    #expect(row.numbers == [3, 5, 6, 9])
    #expect(row[0].windows == [WindowID(7)])
    #expect(row.number(at: row.currentIndex) == 6)
    let taken = row.insert(Workspace(), number: 5)
    #expect(!taken, "5 is taken")
  }

  @Test(arguments: [(5, 6), (6, 9), (9, 6)])
  func removingTheCurrentWorkspaceShowsTheNextOrThePrevious(removed: Int, shown: Int) {
    var row = row()
    row.select(row.index(ofNumber: removed)!)
    let workspace = row.remove(number: removed)
    #expect(workspace?.windows.count == 1)
    #expect(row.number(at: row.currentIndex) == shown)
  }

  @Test func removingKeepsAnotherCurrentWorkspace() {
    var row = row()
    row.select(2)
    _ = row.remove(number: 5)
    #expect(row.number(at: row.currentIndex) == 9)
  }

  @Test func theLastWorkspaceAndUnknownNumbersStay() {
    var single = WorkspaceRow(numbers: [4])
    let only = single.remove(number: 4)
    #expect(only == nil)
    var row = row()
    let unknown = row.remove(number: 7)
    #expect(unknown == nil)
    #expect(row.count == 3)
  }
}
