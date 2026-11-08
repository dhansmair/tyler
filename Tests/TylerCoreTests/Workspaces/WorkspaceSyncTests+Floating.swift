import CoreGraphics
import Testing

@testable import TylerCore

/// Floating windows in the sync: the primary display (workspaces 1 and 2, on 1) and a second one
/// to its right (3 and 4, on 3). Window 1 floats on workspace 1 beside window 2; window 3 floats
/// on the parked workspace 2; window 4 is tiled on workspace 3.
@Suite("WorkspaceSync: floating windows")
struct WorkspaceSyncFloatingTests {
  private let primary = DisplayInfo(
    id: 1, frame: CGRect(x: 0, y: 0, width: 1800, height: 1169),
    visibleFrame: CGRect(x: 55, y: 38, width: 1745, height: 1131))
  private let secondary = DisplayInfo(
    id: 2, frame: CGRect(x: 1800, y: 0, width: 1920, height: 1080),
    visibleFrame: CGRect(x: 1800, y: 0, width: 1920, height: 1080))

  /// A window at `left`: 100 is on the primary display, 2000 on the second.
  private func window(_ id: UInt32, left: CGFloat = 100) -> WindowInfo {
    WindowInfo(
      id: WindowID(id), processID: 1, appName: "App", title: "",
      frame: CGRect(x: left, y: 100, width: 300, height: 200), kind: .standard,
      isMinimized: false, isFullscreen: false, isFocused: false)
  }

  private var windows: [WindowInfo] {
    [window(1), window(2), window(3, left: 3000), window(4, left: 2000)]
  }

  private func rows() -> DisplayRows {
    var rows = DisplayRows(keys: [primary.key, secondary.key], configured: [[1, 2], [3, 4]])
    rows[0][0].sync(eligible: ids(1, 2))
    rows[0][0].float(WindowID(1))
    rows[0][1].sync(eligible: ids(3))
    rows[0][1].float(WindowID(3))
    rows[1][0].sync(eligible: ids(4))
    return rows
  }

  private func plan(
    _ windows: [WindowInfo], floated: Set<WindowID> = []
  ) -> [WorkspaceSync]? {
    WorkspaceSync.plan(
      for: rows(), windows: windows, displays: [primary, secondary],
      marks: WorkspaceSync.Marks(floated: floated, seen: Set(ids(1, 2, 3, 4, 5)), sliding: []),
      assignedWorkspace: { _ in nil })
  }

  @Test func floatingWindowsStayOnTheirWorkspaceShownOrParked() throws {
    let syncs = try #require(plan(windows))
    #expect(syncs[0].eligible == [ids(1, 2), ids(3)])
    #expect(syncs[0].floating == [[], []], "they are members already")
  }

  @Test func aFloatingWindowMovedToTheOtherDisplayGoesLastThereStillFloating() throws {
    var windows = windows
    windows[0] = window(1, left: 2500)
    let syncs = try #require(plan(windows))
    #expect(syncs[0].eligible[0] == ids(2))
    #expect(syncs[1].eligible[0] == ids(4, 1))
    #expect(syncs[1].floating[0] == [WindowID(1)])
  }

  @Test func aWindowFloatedOnNoWorkspaceJoinsItsDisplayFloating() throws {
    let syncs = try #require(plan(windows + [window(5, left: 2000)], floated: [WindowID(5)]))
    #expect(syncs[1].eligible[0] == ids(4, 5))
    #expect(syncs[1].floating[0] == [WindowID(5)])
  }

  @Test func aFloatingWindowWhoseAppHidesStaysWithoutASlot() throws {
    var windows = windows
    windows[0].isHidden = true
    let syncs = try #require(plan(windows))
    #expect(syncs[0].hiding[0] == [WindowID(1)])
    #expect(syncs[0].eligible[0] == ids(2))
  }

  @Test func aMinimizedFloatingWindowLeaves() throws {
    var windows = windows
    windows[0].isMinimized = true
    let syncs = try #require(plan(windows))
    #expect(syncs[0].eligible[0] == ids(2))
  }
}
