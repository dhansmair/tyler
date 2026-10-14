import Testing

@testable import TylerCore

@Suite("WorkspaceRow")
struct WorkspaceRowTests {
  private func makeRow(_ assignments: [Int: [UInt32]], count: Int = 4) -> WorkspaceRow {
    var row = WorkspaceRow(count: count)
    for (index, windows) in assignments {
      row[index].sync(eligible: windows.map(WindowID.init))
    }
    return row
  }

  @Test func startsOnTheFirstOfFourEmptyWorkspaces() {
    let row = WorkspaceRow()
    #expect(row.count == 4)
    #expect(row.currentIndex == 0)
    #expect(row.allWindows.isEmpty)
  }

  @Test func alwaysHasAtLeastOneWorkspace() {
    #expect(WorkspaceRow(count: 0).count == 1)
    #expect(WorkspaceRow(count: -3).count == 1)
  }

  @Test(arguments: [
    (0, WorkspaceTarget.next, 1), (3, .next, 0), (2, .prev, 1), (0, .prev, 3),
    (1, .number(1), 0), (1, .number(4), 3),
  ])
  func resolvesTargetsAndWraps(current: Int, target: WorkspaceTarget, expected: Int) {
    var row = WorkspaceRow()
    row.select(current)
    #expect(row.index(of: target) == expected)
  }

  @Test func growingAddsEmptyWorkspacesAndKeepsTheRest() {
    var row = makeRow([0: [1], 3: [2]])
    row.select(3)
    row.setCount(6)
    #expect(row.count == 6)
    #expect(row.currentIndex == 3)
    #expect(row[3].windows == [WindowID(2)])
    #expect(row[5].windows.isEmpty)
  }

  @Test func shrinkingMergesRemovedWorkspacesIntoTheLastInOrder() {
    var row = makeRow([1: [1, 2], 2: [3], 3: [4, 5]])
    row[1].setFocus(WindowID(1))
    row.setCount(2)
    #expect(row.count == 2)
    #expect(row.currentIndex == 0)
    #expect(
      row[1].windows == [1, 2, 3, 4, 5].map(WindowID.init),
      "appended after the last's own windows, whatever has focus there")
    #expect(row[1].focused == WindowID(1))
  }

  @Test func shrinkingAwayTheCurrentWorkspaceMakesTheLastOneCurrent() {
    var row = makeRow([2: [1], 3: [2]])
    row.select(3)
    row.setCount(2)
    #expect(row.currentIndex == 1)
    #expect(row.current.windows == [WindowID(1), WindowID(2)])
  }

  @Test func neverShrinksBelowOneWorkspace() {
    var row = makeRow([1: [1]])
    row.setCount(0)
    #expect(row.count == 1)
    #expect(row[0].windows == [WindowID(1)])
  }

  @Test(arguments: [0, 5, -1])
  func numbersOutOfRangeResolveToNothing(number: Int) {
    #expect(WorkspaceRow().index(of: .number(number)) == nil)
  }

  @Test func selectRejectsAnIndexOutOfRange() {
    var row = WorkspaceRow()
    let outOfRange = row.select(4)
    #expect(!outOfRange)
    #expect(row.currentIndex == 0)
    let inRange = row.select(2)
    #expect(inRange)
    #expect(row.currentIndex == 2)
  }

  @Test func findsTheWorkspaceOfAWindow() {
    let row = makeRow([0: [1, 2], 2: [3]])
    #expect(row.index(containing: WindowID(2)) == 0)
    #expect(row.index(containing: WindowID(3)) == 2)
    #expect(row.index(containing: WindowID(9)) == nil)
    #expect(row.allWindows == [WindowID(1), WindowID(2), WindowID(3)])
  }

  @Test func currentIsTheSelectedWorkspace() {
    var row = makeRow([1: [5]])
    row.select(1)
    #expect(row.current.windows == [WindowID(5)])
    row.current.insert(WindowID(6))
    #expect(row[1].windows == [WindowID(5), WindowID(6)])
  }

  @Test func movingAWindowInsertsItAfterTheTargetsFocusAndFocusesIt() {
    var row = makeRow([0: [1, 2], 1: [3, 4]])
    row.setFocus(WindowID(3))
    let moved = row.move(WindowID(1), to: 1)
    #expect(moved)
    #expect(row[0].windows == [WindowID(2)])
    #expect(row[1].windows == [WindowID(3), WindowID(1), WindowID(4)])
    #expect(row[1].focused == WindowID(1))
  }

  @Test func movingToAnEmptyWorkspaceWorks() {
    var row = makeRow([0: [1]])
    let moved = row.move(WindowID(1), to: 3)
    #expect(moved)
    #expect(row[3].windows == [WindowID(1)])
    #expect(row[0].count == 0)
  }

  @Test func movingIsRefusedForUnknownWindowsTheSameWorkspaceAndBadIndices() {
    var row = makeRow([0: [1]])
    let unknown = row.move(WindowID(9), to: 1)
    #expect(!unknown)
    let sameWorkspace = row.move(WindowID(1), to: 0)
    #expect(!sameWorkspace)
    let badIndex = row.move(WindowID(1), to: 4)
    #expect(!badIndex)
    #expect(row[0].windows == [WindowID(1)])
  }

  @Test func setFocusActsOnTheWindowsOwnWorkspace() {
    var row = makeRow([0: [1], 2: [7, 8]])
    let known = row.setFocus(WindowID(8))
    #expect(known)
    #expect(row[2].focused == WindowID(8))
    #expect(row[0].focused == nil)
    let unknown = row.setFocus(WindowID(99))
    #expect(!unknown)
  }
}
