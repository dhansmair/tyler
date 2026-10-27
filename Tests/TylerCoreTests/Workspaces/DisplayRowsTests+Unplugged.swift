import Testing

@testable import TylerCore

/// New workspace numbers from the config while the external display is unplugged: the laptop
/// (display 1, workspaces 1 to 4) and the external display (5 to 8), window 10 + n on workspace n.
/// The config is read for the connected displays only.
@Suite("DisplayRows: a display that isn't connected")
struct DisplayRowsUnpluggedTests {
  private let laptop = DisplayKey("laptop")
  private let external = DisplayKey("external")

  private func rows() -> DisplayRows {
    var rows = DisplayRows(keys: [laptop, external], configured: [[1, 2, 3, 4], [5, 6, 7, 8]])
    for position in rows.entries.indices {
      for index in rows[position].indices {
        let number = rows[position].number(at: index)
        rows[position][index].sync(eligible: [WindowID(UInt32(10 + number))])
      }
    }
    return rows
  }

  @Test func itsWorkspacesKeepWaitingAndGoHomeWhenItComesBack() {
    var rows = rows()
    rows.reassign(to: [laptop])
    rows.setConfigured([[1, 2, 3, 4]])
    #expect(rows.entries.map(\.row.numbers) == [[1, 2, 3, 4, 5, 6, 7, 8]])
    #expect(rows[0][4].windows == [WindowID(15)])
    #expect(rows.homes[5] == .configured(2))
    rows.reassign(to: [laptop, external])
    #expect(rows.entries.map(\.row.numbers) == [[1, 2, 3, 4], [5, 6, 7, 8]])
  }

  @Test func aWorkspaceMovedThereByHandKeepsWaitingToo() throws {
    var rows = rows()
    try rows.moveWorkspace(number: 8, to: laptop)
    try rows.moveWorkspace(number: 8, to: external)
    rows.reassign(to: [laptop])
    rows.setConfigured([[1, 2, 3, 4]])
    #expect(rows.location(ofNumber: 8) != nil)
    #expect(rows.homes[8] == .pinned(external))
  }
}
