import CoreGraphics
import Foundation
import Testing

@testable import TylerCore

/// How the state file keeps each workspace's layout states: as one value since version 3, in a
/// field per piece of state before.
@Suite("Saved state: layout states")
struct SavedStateLayoutStatesTests {
  /// `workspace` written to a file and read back, as a tylerd from before version 3 wrote it,
  /// then restored.
  private func restored(_ workspace: SavedState.SavedWorkspace) throws -> Workspace {
    let path = NSTemporaryDirectory() + "tyler-state-\(UUID().uuidString).json"
    defer { try? FileManager.default.removeItem(atPath: path) }
    var state = SavedState(
      row: WorkspaceRow(count: 1), floated: [], tilingEnabled: true, originalFrames: [:])
    state.workspaces = [workspace]
    try state.write(to: path)
    let read = try #require(try SavedState.read(from: path))
    return read.row(count: 1) { _ in true }[0]
  }

  @Test func aFileWithAFieldPerPieceOfStateComesBack() throws {
    let workspace = try restored(
      SavedState.SavedWorkspace(
        windows: ids(1, 2, 3), focused: WindowID(1), layout: .grid, mainRatio: 0.6,
        rowWeights: [[], [2, 1]],
        sizes: [SavedState.SavedSize(id: WindowID(2), size: .full)],
        grid: ColumnWeights(columns: [2, 1])))
    #expect(
      workspace.layoutStates
        == LayoutStates(
          tall: TallLayoutState(mainRatio: 0.6, rowWeights: [[], [2, 1]]),
          grid: GridLayoutState(weights: ColumnWeights(columns: [2, 1])),
          strip: StripLayoutState(sizes: [WindowID(2): .full])))
  }

  @Test func aFileFromBeforeRowWeightsGivesEqualRows() throws {
    let workspace = try restored(
      SavedState.SavedWorkspace(
        windows: ids(1, 2, 3), focused: nil, layout: .tall, mainRatio: 0.6))
    #expect(workspace.layoutStates.tall.rowWeights.isEmpty)
    #expect(workspace.layoutStates.tall.mainRatio == 0.6)
  }

  @Test func aFileFromBeforeTheGridGivesItEqualSizes() throws {
    let workspace = try restored(
      SavedState.SavedWorkspace(
        windows: ids(1, 2), focused: nil, layout: .grid, mainRatio: 0.5,
        rowWeights: [[], [1, 2]]))
    #expect(workspace.layoutStates.grid.weights == ColumnWeights())
  }

  /// As in a file written before that layout existed.
  @Test func aLayoutMissingFromTheFileGetsANewWorkspacesState() throws {
    let states = LayoutStates(
      tall: TallLayoutState(mainRatio: 0.7),
      grid: GridLayoutState(weights: ColumnWeights(columns: [2, 1])))
    let data = try JSONEncoder().encode(states)
    var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    object["grid"] = nil
    let decoded = try JSONDecoder().decode(
      LayoutStates.self, from: try JSONSerialization.data(withJSONObject: object))
    #expect(decoded == LayoutStates(tall: TallLayoutState(mainRatio: 0.7)))
  }

  @Test func aRatioFromTheFileIsClamped() throws {
    let data = Data(#"{"mainRatio": 5, "rowWeights": []}"#.utf8)
    #expect(try JSONDecoder().decode(TallLayoutState.self, from: data).mainRatio == 0.9)
  }

  /// A window that closed while tylerd restarted leaves its states as a closed window does: its
  /// quarter's column mate goes back to half.
  @Test func aWindowGoneAfterARestartLeavesItsStates() {
    var workspace = makeWorkspace(1, 2, 3)
    workspace.setSizeWithPartner(.quarter, of: WindowID(1))
    let saved = SavedState.SavedWorkspace(workspace)
    let restored = saved.workspace { $0 != WindowID(1) }
    #expect(restored.layoutStates.strip.sizes.isEmpty)
  }
}
