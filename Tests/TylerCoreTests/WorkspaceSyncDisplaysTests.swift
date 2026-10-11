import CoreGraphics
import Testing

@testable import TylerCore

/// Syncing every display's row: the primary display (workspaces 1 to 4, on 1) and a second one
/// to its right (5 to 8, on 5). Window 9 is Firefox, assigned to workspace 6.
@Suite("WorkspaceSync: several displays")
struct WorkspaceSyncDisplaysTests {
  private let primary = DisplayInfo(
    id: 1, frame: CGRect(x: 0, y: 0, width: 1800, height: 1169),
    visibleFrame: CGRect(x: 55, y: 38, width: 1745, height: 1131))
  private let secondary = DisplayInfo(
    id: 2, frame: CGRect(x: 1800, y: 0, width: 1920, height: 1080),
    visibleFrame: CGRect(x: 1800, y: 0, width: 1920, height: 1080))

  /// A window at `left`: 100 is on the primary display, 2000 on the second.
  private func window(_ id: UInt32, left: CGFloat = 100) -> WindowInfo {
    WindowInfo(
      id: WindowID(id), processID: 1, appName: id == 9 ? "Firefox" : "App", title: "",
      frame: CGRect(x: left, y: 100, width: 300, height: 200), kind: .standard,
      isMinimized: false, isFullscreen: false, isFocused: false)
  }

  /// Window 1 on workspace 1 and window 2 on workspace 5 (both on screen), window 3 on 6.
  private func rows() -> DisplayRows {
    var rows = DisplayRows(
      keys: [primary.key, secondary.key], configured: [[1, 2, 3, 4], [5, 6, 7, 8]])
    rows[0][0].sync(eligible: [WindowID(1)])
    rows[1][0].sync(eligible: [WindowID(2)])
    rows[1][1].sync(eligible: [WindowID(3)])
    return rows
  }

  private func plan(
    _ rows: DisplayRows, _ windows: [WindowInfo], seen: Set<WindowID> = [],
    sliding: Set<WindowID> = [], held: Set<WindowID> = []
  ) -> [WorkspaceSync]? {
    WorkspaceSync.plan(
      for: rows, windows: windows, displays: [primary, secondary],
      marks: WorkspaceSync.Marks(floated: [], seen: seen, sliding: sliding, held: held),
      assignedWorkspace: { $0.appName == "Firefox" ? 6 : nil })
  }

  /// The windows the workspaces will hold: per display, per workspace.
  private func lists(_ sync: [WorkspaceSync]?) -> [[[UInt32]]]? {
    sync?.map { $0.eligible.map { $0.map(\.rawValue) } }
  }

  @Test func everyDisplayKeepsItsWindows() {
    let sync = plan(rows(), [window(1), window(2, left: 2000), window(3, left: 4000)])
    #expect(lists(sync) == [[[1], [], [], []], [[2], [3], [], []]])
  }

  @Test func aNewWindowJoinsTheCurrentWorkspaceOfItsDisplay() {
    let sync = plan(rows(), [window(1), window(2, left: 2000), window(3), window(4, left: 2500)])
    #expect(lists(sync)?[1][0] == [2, 4])
  }

  @Test func aWindowMovedToTheOtherDisplayGoesLastInItsCurrentWorkspace() {
    let sync = plan(rows(), [window(1, left: 2500), window(2, left: 2000), window(3)])
    #expect(lists(sync)?[0][0] == [])
    #expect(lists(sync)?[1][0] == [2, 1])
    #expect(sync?.allSatisfy(\.arrivals.isEmpty) == true, "nothing is parked")
  }

  @Test(arguments: [true, false])
  func aHeldOrSlidingWindowStaysOnItsWorkspace(isHeld: Bool) {
    let moving: Set<WindowID> = [WindowID(1)]
    let sync = plan(
      rows(), [window(1, left: 2500), window(2, left: 2000), window(3)],
      sliding: isHeld ? [] : moving, held: isHeld ? moving : [])
    #expect(lists(sync)?[0][0] == [1])
    #expect(lists(sync)?[1][0] == [2])
  }

  @Test func anAssignedWindowArrivesOnItsWorkspaceOnTheOtherDisplay() {
    let sync = plan(rows(), [window(1), window(2, left: 2000), window(3), window(9)])
    #expect(lists(sync)?[1][1] == [3, 9])
    #expect(sync?[1].arrivals == [WindowID(9)], "parked on the other display")
    #expect(sync?[0].arrivals == [])
  }

  @Test func anAssignedWindowJoinsItsWorkspaceWhereItIsOnScreen() {
    var rows = rows()
    rows[1].select(1)
    let sync = plan(rows, [window(1), window(2, left: 2000), window(3, left: 2000), window(9)])
    #expect(lists(sync)?[1][1] == [3, 9])
    #expect(sync?[1].arrivals == [], "workspace 6 is on screen")
  }
}
