import Testing

@testable import TylerCore

/// One display showing workspace 1 with windows 1, 2 and 3.
@Suite("DisplayRows: windows leaving")
struct DisplayRowsLeavingTests {
  private let display = DisplayKey("display")

  private func rows() -> DisplayRows {
    var rows = DisplayRows(keys: [display], configured: [[1, 2]])
    rows.focused.current.sync(eligible: [WindowID(1), WindowID(2), WindowID(3)])
    return rows
  }

  @Test func aWindowLeavingIsOnlyALoss() {
    let before = rows()
    var after = before
    after.focused.current.sync(eligible: [WindowID(1), WindowID(3)])
    #expect(after.focusedWorkspaceOnlyLostWindows(since: before))
  }

  @Test func aWindowArrivingIsNot() {
    let before = rows()
    var after = before
    after.focused.current.sync(eligible: [WindowID(1), WindowID(3), WindowID(4)])
    #expect(!after.focusedWorkspaceOnlyLostWindows(since: before))
  }

  @Test func anotherWorkspaceComingIntoViewIsNot() {
    let before = rows()
    var after = before
    after.focused.select(1)
    #expect(!after.focusedWorkspaceOnlyLostWindows(since: before))
  }
}
