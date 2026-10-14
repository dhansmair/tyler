import CoreGraphics
import Testing

@testable import TylerCore

@Suite("WorkspaceSync")
struct WorkspaceSyncTests {
  private let primary = DisplayInfo(
    id: 1, frame: CGRect(x: 0, y: 0, width: 1800, height: 1169),
    visibleFrame: CGRect(x: 55, y: 38, width: 1745, height: 1131))
  private let secondary = DisplayInfo(
    id: 2, frame: CGRect(x: 1800, y: 0, width: 1920, height: 1080),
    visibleFrame: CGRect(x: 1800, y: 0, width: 1920, height: 1080))

  /// Window 9 is Firefox, which the config in `plan` assigns to workspace 3.
  func window(_ id: UInt32, left: CGFloat = 100, kind: WindowKind = .standard) -> WindowInfo {
    WindowInfo(
      id: WindowID(id), processID: 1, appName: id == 9 ? "Firefox" : "App", title: "",
      frame: CGRect(x: left, y: 100, width: 300, height: 200), kind: kind, isMinimized: false,
      isFullscreen: false, isFocused: false)
  }

  private func plan(
    _ row: WorkspaceRow, _ windows: [WindowInfo], displays: [DisplayInfo]? = nil,
    floated: Set<WindowID> = [], seen: Set<WindowID> = [], sliding: Set<WindowID> = []
  ) -> WorkspaceSync? {
    WorkspaceSync.plan(
      for: row, windows: windows, displays: displays ?? [primary, secondary],
      marks: WorkspaceSync.Marks(floated: floated, seen: seen, sliding: sliding),
      assignedWorkspace: { $0.appName == "Firefox" ? 3 : nil })
  }

  private func row(_ lists: [[UInt32]]) -> WorkspaceRow {
    var row = WorkspaceRow(count: 4)
    for (index, list) in lists.enumerated() {
      row[index].sync(eligible: list.map(WindowID.init))
    }
    return row
  }

  @Test func aFirstFillGoesLeftToRight() {
    let sync = plan(WorkspaceRow(count: 4), [window(1, left: 900), window(2, left: 100)])
    #expect(sync?.eligible.first == [WindowID(2), WindowID(1)])
  }

  @Test func floatedAndUntileableWindowsLeave() {
    let sync = plan(
      row([[1, 2, 3]]), [window(1), window(2, kind: .dialog), window(3)],
      floated: [WindowID(3)])
    #expect(sync?.eligible.first == [WindowID(1)])
  }

  @Test func aWindowOnAnotherDisplayLeavesTheCurrentWorkspaceUnlessItIsSliding() {
    let windows = [window(1), window(2, left: 2000)]
    #expect(plan(row([[1, 2]]), windows)?.eligible.first == [WindowID(1)])
    #expect(
      plan(row([[1, 2]]), windows, sliding: [WindowID(2)])?.eligible.first
        == [WindowID(1), WindowID(2)])
  }

  @Test func aParkedWorkspaceKeepsItsWindowsWhereverTheyAre() {
    let sync = plan(row([[1], [2]]), [window(1), window(2, left: 2000)])
    #expect(sync?.eligible[1] == [WindowID(2)])
  }

  @Test func aNewWindowOfAnAssignedAppArrivesOnItsWorkspace() {
    let sync = plan(row([[1]]), [window(1), window(9)])
    #expect(sync?.eligible[2] == [WindowID(9)])
    #expect(sync?.arrivals == [WindowID(9)])
    #expect(sync?.eligible.first == [WindowID(1)])
  }

  @Test func anAssignmentFindsItsWorkspaceByNumber() {
    var numbered = WorkspaceRow(numbers: [2, 3])
    numbered[0].sync(eligible: [WindowID(1)])
    let sync = plan(numbered, [window(1), window(9)])
    #expect(sync?.eligible[1] == [WindowID(9)], "workspace 3 is the row's second")
    #expect(sync?.arrivals == [WindowID(9)])
  }

  @Test func anAssignmentToAWorkspaceTheRowLacksJoinsTheCurrentOne() {
    var numbered = WorkspaceRow(numbers: [5, 6])
    numbered[0].sync(eligible: [WindowID(1)])
    let sync = plan(numbered, [window(1), window(9)])
    #expect(sync?.eligible.first == [WindowID(1), WindowID(9)])
    #expect(sync?.arrivals == [])
  }

  @Test func aWindowSeenBeforeJoinsTheCurrentWorkspaceWhateverItsApp() {
    let sync = plan(row([[1]]), [window(1), window(9)], seen: [WindowID(9)])
    #expect(sync?.eligible.first == [WindowID(1), WindowID(9)])
    #expect(sync?.arrivals == [])
  }

  @Test func withoutADisplayNothingIsDecided() {
    #expect(plan(row([[1]]), [window(1)], displays: []) == nil)
  }
}
