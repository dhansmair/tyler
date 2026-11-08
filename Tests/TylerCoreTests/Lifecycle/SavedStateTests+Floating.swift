import CoreGraphics
import Foundation
import Testing

@testable import TylerCore

/// Floating members of a workspace through the saved state. Workspace 1 holds windows 1, 2 and 3,
/// with 2 floating; window 9 floats on no workspace.
@Suite("Saved state: floating windows")
struct SavedStateFloatingTests {
  private let floatedAt = CGRect(x: 100, y: 100, width: 300, height: 200)

  private let display = DisplayKey("display")

  private func rows() -> DisplayRows {
    var rows = DisplayRows(keys: [display], configured: [[1, 2]])
    rows[0][0].sync(eligible: ids(1, 2, 3))
    rows[0][0].float(WindowID(2))
    rows[0][0].rememberFloatingFrames([Placement(id: WindowID(2), frame: floatedAt)])
    rows[0][0].setFocus(WindowID(2))
    return rows
  }

  private func saved() -> SavedState {
    SavedState(rows: rows(), floated: [WindowID(9)], tilingEnabled: true, originalFrames: [:])
  }

  @Test func aFloatingWindowComesBackFloatingInItsPlaceAndWhereItWas() throws {
    let path = NSTemporaryDirectory() + "tyler-state-\(UUID().uuidString)/tyler.state.json"
    defer { try? FileManager.default.removeItem(atPath: path) }
    try saved().write(to: path)
    let read = try #require(try SavedState.read(from: path))
    let restored = read.rows(count: 2) { _ in true }[0][0]
    #expect(restored.members == ids(1, 2, 3))
    #expect(restored.floating == [WindowID(2)])
    #expect(restored.floatingFrame(of: WindowID(2)) == floatedAt)
    #expect(restored.lastFocused == WindowID(2), "it had the focus")
  }

  @Test func anOlderTylerdSeesEveryFloatedWindowAsFloated() {
    #expect(saved().floated == ids(2, 9))
  }

  @Test func onlyTheWindowsOnNoWorkspaceFloatOnNone() {
    #expect(saved().floatedOnNoWorkspace == [WindowID(9)])
  }

  @Test func aFileFromBeforeFloatingMembersFloatsItsWindowsOnNoWorkspace() {
    var old = SavedState(
      rows: DisplayRows(keys: [display], configured: [[1]]), floated: [], tilingEnabled: true,
      originalFrames: [:])
    old.floated = ids(2)
    #expect(old.floatedOnNoWorkspace == [WindowID(2)])
  }

  @Test func aLateFloatingWindowGoesBackFloatingInItsPlace() {
    var late = LateHandOver(saved(), taken: Set(ids(1, 3)))
    var rows = DisplayRows(keys: [display], configured: [[1, 2]])
    rows[0][0].sync(eligible: ids(1, 3))
    var floated: Set<WindowID> = []
    let window = WindowInfo(
      id: WindowID(2), processID: 1, appName: "App", title: "", frame: floatedAt, kind: .standard,
      isMinimized: false, isFullscreen: false, isFocused: false)
    late.restore([window], into: &rows, floated: &floated)
    #expect(rows[0][0].members == ids(1, 2, 3))
    #expect(rows[0][0].floating == [WindowID(2)])
    #expect(rows[0][0].floatingFrame(of: WindowID(2)) == floatedAt)
    #expect(floated.isEmpty)
  }
}
