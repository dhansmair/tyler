import CoreGraphics
import Foundation
import Testing

@testable import TylerCore

@Suite("Saved state")
struct SavedStateTests {
  /// Workspace 1: windows 1, 2, 3 (2 focused), tall at 0.6 with the row split 2:1;
  /// workspace 3: window 4, full; the third workspace is current.
  private func arrangement() -> WorkspaceRow {
    var row = WorkspaceRow(count: 4)
    var first = Workspace(
      layout: .tall,
      layoutStates: LayoutStates(tall: TallLayoutState(mainRatio: 0.6, rowWeights: [[], [2, 1]])))
    for raw in [1, 2, 3] as [UInt32] { first.insert(WindowID(raw)) }
    first.setFocus(WindowID(2))
    row[0] = first
    var third = Workspace(layout: .full)
    third.insert(WindowID(4))
    row[2] = third
    row.select(2)
    return row
  }

  private func saved(_ row: WorkspaceRow) -> SavedState {
    SavedState(
      row: row, floated: [WindowID(9)], tilingEnabled: true,
      originalFrames: [WindowID(1): CGRect(x: 10, y: 20, width: 300, height: 200)])
  }

  @Test func aStackComesBackAsItWas() {
    let row = arrangement()
    #expect(saved(row).row(count: 4) { _ in true } == row)
  }

  @Test func windowsThatClosedAreDroppedAndFocusMovesOn() {
    let restored = saved(arrangement()).row(count: 4) { $0 != WindowID(2) }
    #expect(restored[0].windows == [WindowID(1), WindowID(3)])
    #expect(restored[0].focused == nil, "the focused window closed")
    #expect(restored[2].windows == [WindowID(4)])
  }

  @Test func fewerWorkspacesMergeTheRestIntoTheLast() {
    let restored = saved(arrangement()).row(count: 2) { _ in true }
    #expect(restored.count == 2)
    #expect(restored.currentIndex == 1, "the current workspace was merged into the last")
    #expect(restored[0].windows == [WindowID(1), WindowID(2), WindowID(3)])
    #expect(restored[1].windows == [WindowID(4)])
  }

  @Test func moreWorkspacesAddEmptyOnes() {
    let restored = saved(arrangement()).row(count: 6) { _ in true }
    #expect(restored.count == 6)
    #expect(restored.currentIndex == 2)
    #expect(restored[5].windows.isEmpty)
  }

  @Test func theFileRoundTrips() throws {
    let path = NSTemporaryDirectory() + "tyler-state-\(UUID().uuidString)/tyler.state.json"
    defer { try? FileManager.default.removeItem(atPath: path) }
    let state = saved(arrangement())
    try state.write(to: path)
    #expect(try SavedState.read(from: path) == state)
  }

  @Test func theGridsSizesComeBack() {
    var row = WorkspaceRow(count: 1)
    var grid = Workspace(
      layout: .grid,
      layoutStates: LayoutStates(
        grid: GridLayoutState(weights: ColumnWeights(columns: [2, 1], rows: [[1, 3]]))))
    for raw in [1, 2, 3, 4] as [UInt32] { grid.insert(WindowID(raw)) }
    row[0] = grid
    let restored = saved(row).row(count: 1) { _ in true }
    #expect(
      restored[0].layoutStates.grid.weights == ColumnWeights(columns: [2, 1], rows: [[1, 3]]))
  }

  /// One workspace holding the state of every layout at once comes back whole from the file:
  /// tall's ratio and rows, the grid's sizes, the strip's sizes and its view.
  @Test func everyLayoutsStateComesBackFromTheFile() throws {
    let path = NSTemporaryDirectory() + "tyler-state-\(UUID().uuidString).json"
    defer { try? FileManager.default.removeItem(atPath: path) }
    var workspace = Workspace(
      layout: .strip,
      layoutStates: LayoutStates(
        tall: TallLayoutState(mainRatio: 0.7, rowWeights: [[], [1, 3]]),
        grid: GridLayoutState(weights: ColumnWeights(columns: [2, 1], rows: [[1, 3]]))))
    for raw in [1, 2, 3, 4, 5, 6] as [UInt32] { workspace.append(WindowID(raw)) }
    workspace.setSize(.full, of: WindowID(1))
    workspace.setSizeWithPartner(.quarter, of: WindowID(3))
    // Through 6 and back to 5 leaves the view at 5, further right than refitting it from the
    // left would put it.
    workspace.setFocus(WindowID(6))
    workspace.setFocus(WindowID(5))
    var row = WorkspaceRow(count: 1)
    row[0] = workspace
    try saved(row).write(to: path)

    let state = try #require(try SavedState.read(from: path))
    #expect(state.row(count: 1) { _ in true } == row)
  }

  @Test func noFileIsNoState() throws {
    #expect(try SavedState.read(from: "/tmp/tyler-no-such-state.json") == nil)
  }

  @Test func anotherVersionIsRefused() throws {
    let path = NSTemporaryDirectory() + "tyler-state-\(UUID().uuidString).json"
    defer { try? FileManager.default.removeItem(atPath: path) }
    var state = saved(arrangement())
    state.version = SavedState.currentVersion + 1
    try state.write(to: path)
    #expect(throws: SavedStateError.unknownVersion(path: path, version: state.version)) {
      try SavedState.read(from: path)
    }
  }

  @Test(arguments: [(0.0, true), (SavedState.maximumAge, true), (SavedState.maximumAge + 1, false)])
  func aFileLeftBehindTooLongIsRefused(age: TimeInterval, isRead: Bool) throws {
    let path = NSTemporaryDirectory() + "tyler-state-\(UUID().uuidString).json"
    defer { try? FileManager.default.removeItem(atPath: path) }
    var state = saved(arrangement())
    let writtenAt = Date(timeIntervalSinceReferenceDate: 1_000_000)
    state.writtenAt = writtenAt
    try state.write(to: path)
    let now = writtenAt.addingTimeInterval(age)
    if isRead {
      #expect(try SavedState.read(from: path, now: now) == state)
    } else {
      #expect(throws: SavedStateError.stale(path: path, writtenAt: writtenAt)) {
        try SavedState.read(from: path, now: now)
      }
    }
  }

  @Test func aFileFromBefore010HasNoTimeAndIsRead() throws {
    let path = NSTemporaryDirectory() + "tyler-state-\(UUID().uuidString).json"
    defer { try? FileManager.default.removeItem(atPath: path) }
    let state = saved(arrangement())
    try state.write(to: path)
    #expect(try SavedState.read(from: path, now: .distantFuture) == state)
  }

  @Test func aBrokenFileIsAnError() throws {
    let path = NSTemporaryDirectory() + "tyler-state-\(UUID().uuidString).json"
    defer { try? FileManager.default.removeItem(atPath: path) }
    try Data("{".utf8).write(to: URL(fileURLWithPath: path))
    #expect(throws: SavedStateError.self) { try SavedState.read(from: path) }
  }

  @Test func theSlotsOfFloatedWindowsRoundTrip() throws {
    let path = NSTemporaryDirectory() + "tyler-state-\(UUID().uuidString)/tyler.state.json"
    defer { try? FileManager.default.removeItem(atPath: path) }
    let state = SavedState(
      rows: DisplayRows(keys: [DisplayKey("display")], configured: [[1]]), floated: [WindowID(9)],
      tilingEnabled: true, originalFrames: [:], floatedSlots: [WindowID(9): 2])
    try state.write(to: path)
    let read = try #require(try SavedState.read(from: path))
    #expect(read.floatedSlots == [SavedState.FloatedSlot(id: WindowID(9), slot: 2)])
  }
}
