import Foundation
import Testing

@testable import TylerCore

/// Version 2 of the saved state: a row per display.
@Suite("Saved state: displays")
struct SavedStateDisplaysTests {
  private let laptop = DisplayKey("laptop")
  private let external = DisplayKey("external")

  /// The laptop with 1 to 4 and the external display with 5 to 8; window 1 on workspace 2 (on
  /// screen), windows 5 and 6 on workspace 6 (on screen), workspace 3 pinned to the external
  /// display, which has the focus.
  private func rows() throws -> DisplayRows {
    var rows = DisplayRows(keys: [laptop, external], configured: [[1, 2, 3, 4], [5, 6, 7, 8]])
    rows[0][1].sync(eligible: [WindowID(1)])
    rows[0].select(1)
    rows[1][1].sync(eligible: [WindowID(5), WindowID(6)])
    rows[1][1].layout = .full
    rows[1].select(1)
    try rows.moveWorkspace(number: 3, to: external)
    rows[1].select(rows[1].index(ofNumber: 6) ?? 0)
    return rows
  }

  private func saved(_ rows: DisplayRows) -> SavedState {
    SavedState(rows: rows, floated: [], tilingEnabled: true, originalFrames: [:])
  }

  @Test func everyDisplaysRowComesBackThroughTheFile() throws {
    let path = NSTemporaryDirectory() + "tyler-state-\(UUID().uuidString).json"
    defer { try? FileManager.default.removeItem(atPath: path) }
    let rows = try rows()
    try saved(rows).write(to: path)
    let state = try #require(try SavedState.read(from: path))
    #expect(state.version == 3)
    #expect(state.rows(count: 4) { _ in true } == rows)
  }

  @Test func windowsThatClosedAreLeftOut() throws {
    let restored = saved(try rows()).rows(count: 4) { $0 != WindowID(5) }
    #expect(restored[1][restored[1].currentIndex].windows == [WindowID(6)])
  }

  @Test func aVersionOneStateIsOneRowOnADisplayNotYetKnown() {
    var row = WorkspaceRow(count: 3)
    row[2].sync(eligible: [WindowID(4)])
    row.select(2)
    let old = SavedState(row: row, floated: [], tilingEnabled: true, originalFrames: [:])
    #expect(old.version == 1)
    let restored = old.rows(count: 4) { _ in true }
    #expect(restored.keys == [DisplayRows.unknownDisplay])
    #expect(restored[0].numbers == [1, 2, 3, 4])
    #expect(restored[0].currentIndex == 2)
    #expect(restored.homes[4] == .configured(1))
  }
}
