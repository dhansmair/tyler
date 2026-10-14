import Testing

@testable import TylerCore

private let half = WindowSize.half
private let full = WindowSize.full
private let quarter = WindowSize.quarter

@Suite("Strip layout: window sizes")
struct WindowSizeTests {
  @Test func windowsStartHalf() {
    #expect(makeWorkspace(1).size(of: WindowID(1)) == half)
  }

  @Test func setSizeNeedsATiledWindowAndAChange() {
    var workspace = makeWorkspace(1)
    let changed = workspace.setSize(full, of: WindowID(1))
    let again = workspace.setSize(full, of: WindowID(1))
    let untiled = workspace.setSize(full, of: WindowID(9))
    #expect(changed)
    #expect(!again, "already full")
    #expect(!untiled, "not tiled here")
    #expect(workspace.size(of: WindowID(1)) == full)
  }

  @Test func aWindowThatLeavesForgetsItsSize() {
    var workspace = makeWorkspace(1, 2)
    workspace.setSize(full, of: WindowID(2))
    workspace.remove(WindowID(2))
    workspace.insert(WindowID(2))
    #expect(workspace.size(of: WindowID(2)) == half)
  }

  @Test func aWindowKeepsItsSizeOnAnotherWorkspace() {
    var row = WorkspaceRow()
    row[0].insert(WindowID(1))
    row[0].setSize(full, of: WindowID(1))
    row.move(WindowID(1), to: 2)
    #expect(row[2].size(of: WindowID(1)) == full)
    #expect(row[0].layoutStates.strip.sizes.isEmpty)
  }

  @Test func aQuarterArrivesHalfAndLeavesItsMateHalf() {
    var row = WorkspaceRow()
    row[0] = makeWorkspace(1, 2)
    row[0].setSizeWithPartner(quarter, of: WindowID(1))
    row.move(WindowID(1), to: 2)
    #expect(row[2].size(of: WindowID(1)) == half)
    #expect(row[0].size(of: WindowID(2)) == half)
  }

  // MARK: - Pairing quarters

  private func sizes(_ workspace: Workspace) -> [WindowSize] {
    workspace.windows.map(workspace.size(of:))
  }

  @Test func aQuarterTakesTheNextWindowAlong() {
    var workspace = makeWorkspace(1, 2, 3)
    #expect(workspace.setSizeWithPartner(quarter, of: WindowID(1)) == .changed)
    #expect(sizes(workspace) == [quarter, quarter, half])
  }

  @Test func theLastWindowPairsWithThePreviousOne() {
    var workspace = makeWorkspace(1, 2, 3)
    workspace.setSizeWithPartner(quarter, of: WindowID(3))
    #expect(sizes(workspace) == [half, quarter, quarter])
  }

  @Test func aWindowBeforeAPairPairsWithThePreviousOne() {
    var workspace = makeWorkspace(1, 2, 3, 4)
    workspace.setSizeWithPartner(quarter, of: WindowID(3))
    #expect(workspace.setSizeWithPartner(quarter, of: WindowID(2)) == .changed)
    #expect(sizes(workspace) == [quarter, quarter, quarter, quarter])
    #expect(StripColumns(sizes: sizes(workspace)).columns == [[0, 1], [2, 3]])
  }

  @Test func aQuarterNeedsAFreeNeighbour() {
    var single = makeWorkspace(1)
    #expect(single.setSizeWithPartner(quarter, of: WindowID(1)) == .noPartner)
    var hemmed = makeWorkspace(1, 2, 3, 4, 5)
    hemmed.setSizeWithPartner(quarter, of: WindowID(1))
    hemmed.setSizeWithPartner(quarter, of: WindowID(4))
    #expect(hemmed.setSizeWithPartner(quarter, of: WindowID(3)) == .noPartner)
    #expect(sizes(hemmed) == [quarter, quarter, half, quarter, quarter])
  }

  @Test func leavingAPairPutsTheMateBackToHalf() {
    var workspace = makeWorkspace(1, 2, 3)
    workspace.setSizeWithPartner(quarter, of: WindowID(1))
    #expect(workspace.setSizeWithPartner(full, of: WindowID(2)) == .changed)
    #expect(sizes(workspace) == [half, full, half])
  }

  @Test func closingOneOfAPairPutsTheOtherBackToHalf() {
    var workspace = makeWorkspace(1, 2, 3)
    workspace.setSizeWithPartner(quarter, of: WindowID(1))
    workspace.remove(WindowID(2))
    #expect(sizes(workspace) == [half, half])
  }

  /// Floating or minimizing a window takes it out of tiling through `sync`, not `remove`.
  @Test func aQuarterThatStopsTilingPutsItsMateBackToHalf() {
    var workspace = makeWorkspace(1, 2, 3)
    workspace.setSizeWithPartner(quarter, of: WindowID(1))
    workspace.sync(eligible: ids(2, 3))
    #expect(sizes(workspace) == [half, half])
  }

  @Test func settingTheSameSizeChangesNothing() {
    var workspace = makeWorkspace(1, 2)
    #expect(workspace.setSizeWithPartner(half, of: WindowID(1)) == .unchanged)
    #expect(workspace.setSizeWithPartner(full, of: WindowID(9)) == .unchanged)
  }
}
