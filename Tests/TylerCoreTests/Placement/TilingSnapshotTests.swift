import CoreGraphics
import Testing

@testable import TylerCore

/// Two displays side by side, 1000 × 600 each: the laptop (workspaces 1 and 2) and the external
/// display (3 and 4). Workspace 1 holds windows 1 and 2, workspace 2 window 3 (parked), and
/// workspace 3 holds the strip 4, 5, 6, 7, of which 4 and 5 are in view.
@Suite("TilingSnapshot")
struct TilingSnapshotTests {
  private let laptop = DisplayInfo(
    id: 1, key: DisplayKey("laptop"), frame: CGRect(x: 0, y: 0, width: 1000, height: 600),
    visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 600))
  private let external = DisplayInfo(
    id: 2, key: DisplayKey("external"), frame: CGRect(x: 1000, y: 0, width: 1000, height: 600),
    visibleFrame: CGRect(x: 1000, y: 0, width: 1000, height: 600))
  private let gaps = LayoutGaps()

  private var rows: DisplayRows {
    var rows = DisplayRows(keys: [laptop.key, external.key], configured: [[1, 2], [3, 4]])
    rows[0][0].sync(eligible: ids(1, 2))
    rows[0][1].sync(eligible: ids(3))
    var strip = Workspace(layout: .strip)
    for value in UInt32(4)...7 { strip.append(WindowID(value)) }
    strip.setFocus(WindowID(4))
    rows[1][0] = strip
    return rows
  }

  private func snapshot(connected: [DisplayInfo]? = nil) -> TilingSnapshot {
    TilingSnapshot(
      rows: rows, displays: DisplayArrangement.sided(connected ?? [laptop, external]), gaps: gaps)
  }

  @Test func aWindowIsOnScreenOnlyOnItsDisplaysCurrentWorkspace() {
    let snapshot = snapshot()
    #expect(snapshot.onScreenPosition(of: WindowID(2)) == 0)
    #expect(snapshot.onScreenPosition(of: WindowID(6)) == 1, "out of view, but current")
    #expect(snapshot.onScreenPosition(of: WindowID(3)) == nil, "parked workspace")
    #expect(snapshot.onScreenPosition(of: WindowID(99)) == nil)
  }

  @Test func aSlotIsWhereTheLayoutPutsAWindowInView() throws {
    let snapshot = snapshot()
    let slot = try #require(snapshot.slot(of: WindowID(2)))
    #expect(laptop.visibleFrame.contains(slot.frame))
    #expect(snapshot.currentPlacements(holding: WindowID(1))?.map(\.id) == ids(1, 2))
    #expect(snapshot.slot(of: WindowID(6)) == nil, "out of view")
    #expect(snapshot.slot(of: WindowID(3)) == nil, "parked workspace")
  }

  @Test func onlyAScrollingLayoutHasWindowsOutOfView() {
    let snapshot = snapshot()
    #expect(snapshot.offViewWindows == Set(ids(6, 7)))
    #expect(snapshot.tiledWindowsInView == Set(ids(1, 2, 4, 5)))
  }

  @Test func restingPlacementsParkTheWindowsOutOfView() {
    let snapshot = snapshot()
    let resting = snapshot.restingPlacements(on: [external.key])
    #expect(resting.map(\.id) == ids(4, 5, 6, 7))
    for placement in resting where [6, 7].contains(placement.id.rawValue) {
      #expect(Parking.isParked(placement.frame, on: snapshot.display(at: 1)!))
    }
    #expect(snapshot.restingPlacements().count == 6)
  }

  @Test func aWindowOfAParkedWorkspaceWaitsAtItsSlotsParkingSpot() throws {
    let snapshot = snapshot()
    let placement = try #require(
      snapshot.parkingPlacement(of: WindowID(3), size: CGSize(width: 10, height: 10)))
    #expect(Parking.isParked(placement.frame, on: snapshot.display(at: 0)!))
    #expect(
      placement.frame.height == laptop.visibleFrame.height, "the slot's size, not the window's")
  }

  @Test func aWindowWithoutASlotWaitsWithItsOwnSize() throws {
    let size = CGSize(width: 300, height: 200)
    let placement = try #require(snapshot().parkingPlacement(of: WindowID(7), size: size))
    #expect(placement.frame.size == size)
  }

  @Test func aDisconnectedDisplaysRowAnswersNothing() {
    let snapshot = snapshot(connected: [laptop])
    #expect(snapshot.display(at: 1) == nil)
    #expect(snapshot.slot(of: WindowID(4)) == nil)
    #expect(snapshot.parkingPlacement(of: WindowID(4), size: .zero) == nil)
    #expect(snapshot.offViewWindows.isEmpty)
    #expect(snapshot.tiledWindowsInView == Set(ids(1, 2)))
    #expect(snapshot.restingPlacements().map(\.id) == ids(1, 2))
  }
}
