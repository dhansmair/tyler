import Testing

@testable import TylerCore

/// The laptop (`laptop`, display 1) and the Dell (`dell`), with workspaces 1 to 4 configured on the
/// laptop and 5 to 8 on the Dell. Window 10 + n starts on workspace n.
@Suite("DisplayRows")
struct DisplayRowsTests {
  private let laptop = DisplayKey("laptop")
  private let dell = DisplayKey("dell")
  private let configured = [[1, 2, 3, 4], [5, 6, 7, 8]]

  private func rows(_ keys: [DisplayKey]? = nil) -> DisplayRows {
    var rows = DisplayRows(keys: keys ?? [laptop, dell], configured: configured)
    for position in rows.entries.indices {
      for index in rows[position].indices {
        let number = rows[position].number(at: index)
        rows[position][index].sync(eligible: [WindowID(UInt32(10 + number))])
      }
    }
    return rows
  }

  private func numbers(_ rows: DisplayRows) -> [[Int]] {
    rows.entries.map(\.row.numbers)
  }

  /// The number of the workspace on screen on each display.
  private func current(_ rows: DisplayRows) -> [Int] {
    rows.entries.map { $0.row.number(at: $0.row.currentIndex) }
  }

  private func show(_ number: Int, in rows: inout DisplayRows) {
    guard let location = rows.location(ofNumber: number) else {
      Issue.record("no workspace \(number)")
      return
    }
    rows[location.position].select(location.index)
  }

  @Test func eachDisplayGetsItsConfiguredWorkspaces() {
    let rows = rows()
    #expect(rows.keys == [laptop, dell])
    #expect(numbers(rows) == [[1, 2, 3, 4], [5, 6, 7, 8]])
    #expect(current(rows) == [1, 5])
    #expect(rows.focusedKey == laptop)
  }

  @Test func theWorkspacesOfADisplayThatIsNotConnectedStartOnDisplayOne() {
    #expect(numbers(rows([laptop])) == [[1, 2, 3, 4, 5, 6, 7, 8]])
  }

  @Test func aDisplayTheConfigDoesNotListGetsAWorkspaceOfItsOwn() {
    let projector = DisplayKey("projector")
    #expect(numbers(rows([laptop, dell, projector])) == [[1, 2, 3, 4], [5, 6, 7, 8], [9]])
  }

  @Test func withoutDisplaysThereIsOneUnknownOne() {
    let rows = DisplayRows(keys: [], configured: [[1, 2]])
    #expect(rows.keys == [DisplayRows.unknownDisplay])
    #expect(numbers(rows) == [[1, 2]])
  }

  @Test func lookupsFindWorkspacesAndWindowsOnEveryDisplay() {
    let rows = rows()
    #expect(rows.location(ofNumber: 6)! == (1, 1))
    #expect(rows.location(of: WindowID(13))! == (0, 2))
    #expect(rows.location(ofNumber: 9) == nil)
    #expect(rows.allWindows.count == 8)
  }

  @Test func unpluggingMovesTheWorkspacesToDisplayOneWithTheirWindows() {
    var rows = rows()
    show(2, in: &rows)
    show(6, in: &rows)
    let changed = rows.reassign(to: [laptop])
    #expect(changed)
    #expect(numbers(rows) == [[1, 2, 3, 4, 5, 6, 7, 8]])
    #expect(current(rows) == [2], "the laptop keeps its workspace")
    #expect(rows[0][5].windows == [WindowID(16)])
    #expect(rows.rememberedCurrent == [dell: 6])
  }

  @Test func pluggingBackReturnsTheWorkspacesWithWhatWasOnScreen() {
    var rows = rows()
    show(2, in: &rows)
    show(6, in: &rows)
    rows.reassign(to: [laptop])
    rows.reassign(to: [laptop, dell])
    #expect(numbers(rows) == [[1, 2, 3, 4], [5, 6, 7, 8]])
    #expect(current(rows) == [2, 6])
    #expect(rows.rememberedCurrent.isEmpty)
  }

  @Test func aVisitingWorkspaceOnScreenStaysOnScreenWhenItGoesHome() {
    var rows = rows()
    rows.reassign(to: [laptop])
    show(7, in: &rows)
    rows.reassign(to: [laptop, dell])
    #expect(current(rows) == [4, 7], "the laptop shows the last before 7, the Dell keeps 7")
  }

  @Test func closingTheLidPutsEverythingOnTheOtherDisplay() {
    var rows = rows()
    show(3, in: &rows)
    rows.reassign(to: [dell])
    #expect(numbers(rows) == [[1, 2, 3, 4, 5, 6, 7, 8]])
    #expect(current(rows) == [5], "the Dell keeps its workspace")
    rows.reassign(to: [laptop, dell])
    #expect(numbers(rows) == [[1, 2, 3, 4], [5, 6, 7, 8]])
    #expect(current(rows) == [3, 5])
  }

  @Test func theFocusFallsBackToDisplayOneWhenItsDisplayGoes() {
    var rows = rows()
    let focused = rows.focus(dell)
    #expect(focused)
    #expect(rows.focused.numbers == [5, 6, 7, 8])
    rows.reassign(to: [laptop])
    #expect(rows.focusedKey == laptop)
    let refocused = rows.focus(dell)
    #expect(!refocused, "the Dell isn't connected")
  }

  @Test func theSameDisplaysChangeNothing() {
    var rows = rows()
    let same = rows.reassign(to: [laptop, dell])
    let none = rows.reassign(to: [])
    #expect(!same)
    #expect(!none)
  }

  @Test func aMovedWorkspaceBecomesCurrentThereAndItsOldDisplayShowsTheNext() throws {
    var rows = rows()
    show(3, in: &rows)
    try rows.moveWorkspace(number: 3, to: dell)
    #expect(numbers(rows) == [[1, 2, 4], [3, 5, 6, 7, 8]])
    #expect(current(rows) == [4, 3])
    #expect(rows.focusedKey == dell)
    #expect(rows.homes[3] == .pinned(dell))
  }

  @Test func aMovedWorkspaceFollowsItsNewDisplayThroughUnplugging() throws {
    var rows = rows()
    try rows.moveWorkspace(number: 3, to: dell)
    rows.reassign(to: [laptop])
    #expect(numbers(rows) == [[1, 2, 3, 4, 5, 6, 7, 8]])
    rows.reassign(to: [laptop, dell])
    #expect(numbers(rows) == [[1, 2, 4], [3, 5, 6, 7, 8]])
    #expect(current(rows)[1] == 3)
  }

  @Test func movingAWorkspaceIsRefusedWhenItCannotBeDone() throws {
    var rows = rows()
    #expect(throws: DisplayRows.MoveError.noSuchWorkspace) {
      try rows.moveWorkspace(number: 9, to: dell)
    }
    #expect(throws: DisplayRows.MoveError.noSuchDisplay) {
      try rows.moveWorkspace(number: 1, to: DisplayKey("projector"))
    }
    #expect(throws: DisplayRows.MoveError.alreadyThere) {
      try rows.moveWorkspace(number: 1, to: laptop)
    }
    for number in [6, 7, 8] { try rows.moveWorkspace(number: number, to: laptop) }
    #expect(throws: DisplayRows.MoveError.lastWorkspace) {
      try rows.moveWorkspace(number: 5, to: laptop)
    }
    #expect(numbers(rows) == [[1, 2, 3, 4, 6, 7, 8], [5]])
  }

  @Test func aDisplayArrivingWithoutWorkspacesGetsAnEmptyOne() {
    var rows = rows()
    let projector = DisplayKey("projector")
    rows.reassign(to: [laptop, dell, projector])
    #expect(numbers(rows) == [[1, 2, 3, 4], [5, 6, 7, 8], [9]])
    #expect(rows[2][0].windows.isEmpty)
    #expect(rows.homes[9] == .pinned(projector))
    rows.reassign(to: [laptop, dell])
    rows.reassign(to: [laptop, dell, projector])
    #expect(numbers(rows) == [[1, 2, 3, 4], [5, 6, 7, 8], [9]], "9 went home, no new one")
  }

  @Test func newConfiguredNumbersRenumberTheRowsAndMergeTheWindowsOfThoseThatGo() {
    var rows = rows()
    show(2, in: &rows)
    rows.setConfigured([[1, 2, 9], [5, 6]])
    #expect(numbers(rows) == [[1, 2, 9], [5, 6]])
    #expect(rows[0][2].windows == [WindowID(13), WindowID(14)], "3 and 4 merged into the last")
    #expect(rows[1][1].windows == [WindowID(16), WindowID(17), WindowID(18)])
    #expect(current(rows) == [2, 5])
  }

  @Test func newConfiguredNumbersMoveWorkspacesButKeepThoseMovedByHand() throws {
    var rows = rows()
    try rows.moveWorkspace(number: 3, to: dell)
    rows.setConfigured([[1, 2, 3], [4, 5, 6, 7, 8]])
    #expect(numbers(rows) == [[1, 2], [3, 4, 5, 6, 7, 8]])
    #expect(rows.homes[3] == .pinned(dell))
    #expect(rows.homes[4] == .configured(2))
  }

  @Test func aDisplayWhoseWorkspacesAllGoGetsANewOneWithTheirWindows() {
    var rows = rows()
    rows.setConfigured([[1, 2, 3, 4]])
    #expect(numbers(rows) == [[1, 2, 3, 4], [9]])
    #expect(rows[1][0].windows == [15, 16, 17, 18].map(WindowID.init))
    #expect(rows.homes[9] == .pinned(dell))
  }

  @Test func aWindowMovesToAWorkspaceOnAnotherDisplay() {
    var rows = rows()
    let moved = rows.moveWindow(WindowID(12), toNumber: 6)
    #expect(moved)
    #expect(rows[0][1].windows.isEmpty)
    #expect(rows[1][1].windows == [WindowID(16), WindowID(12)])
    #expect(rows[1][1].focused == WindowID(12))
  }

  @Test func movingAWindowWithinItsDisplayWorksToo() {
    var rows = rows()
    let moved = rows.moveWindow(WindowID(12), toNumber: 3)
    #expect(moved)
    #expect(rows[0][2].windows == [WindowID(13), WindowID(12)])
  }

  @Test(arguments: [(12, 2), (12, 9), (99, 6)])
  func movingAWindowIsRefusedWhenThereIsNothingToDo(window: UInt32, number: Int) {
    var rows = rows()
    let moved = rows.moveWindow(WindowID(window), toNumber: number)
    #expect(!moved)
  }
}
