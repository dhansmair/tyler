import CoreGraphics
import Testing

@testable import TylerCore

@Suite("LateHandOver")
struct LateHandOverTests {
  private static let frame = CGRect(x: 10, y: 20, width: 300, height: 200)
  private var frame: CGRect { Self.frame }

  /// Windows 1, 2 and 3 on workspace 1, with 2 focused, window 4 on workspace 2 and window 5
  /// floated; window 2 has an original frame.
  private let saved: SavedState = {
    var row = WorkspaceRow(count: 3)
    row[0].sync(eligible: [WindowID(1), WindowID(2), WindowID(3)])
    row[0].setFocus(WindowID(2))
    row[1].sync(eligible: [WindowID(4)])
    return SavedState(
      row: row, floated: [WindowID(5)], tilingEnabled: true,
      originalFrames: [WindowID(2): frame])
  }()

  private func window(_ id: UInt32, isMinimized: Bool = false, processID: Int32 = 1) -> WindowInfo {
    WindowInfo(
      id: WindowID(id), processID: processID, appName: "App", title: "",
      frame: CGRect(x: 100, y: 100, width: 300, height: 200), kind: .standard,
      isMinimized: isMinimized, isFullscreen: false, isFocused: false)
  }

  /// The rows and the late part of `saved` when only `taken` were there.
  private func takenOver(_ taken: Set<UInt32>) -> (DisplayRows, LateHandOver) {
    let ids = Set(taken.map(WindowID.init))
    return (saved.rows(count: 3) { ids.contains($0) }, LateHandOver(saved, taken: ids))
  }

  private func windows(_ rows: DisplayRows, _ index: Int) -> [UInt32] {
    rows[0][index].windows.map(\.rawValue)
  }

  @Test func aWindowThereLaterGoesBackBeforeTheOneThatFollowedIt() {
    var (rows, late) = takenOver([1, 3, 4])
    var floated: Set<WindowID> = []
    let outcome = late.restore([window(1), window(2), window(3)], into: &rows, floated: &floated)
    #expect(outcome.restored == [WindowID(2)])
    #expect(outcome.originalFrames == [WindowID(2): frame])
    #expect(windows(rows, 0) == [1, 2, 3])
    #expect(windows(rows, 1) == [4])
  }

  @Test func aWorkspaceComingBackOneWindowAtATimeKeepsItsOrderAndFocus() {
    var (rows, late) = takenOver([])
    var floated: Set<WindowID> = []
    for id: UInt32 in [3, 1, 4, 2] {
      late.restore([window(id)], into: &rows, floated: &floated)
    }
    #expect(windows(rows, 0) == [1, 2, 3])
    #expect(windows(rows, 1) == [4])
    #expect(rows[0][0].focused == WindowID(2))
  }

  @Test func aWindowThatCantBeTiledYetWaits() {
    var (rows, late) = takenOver([1, 3, 4])
    var floated: Set<WindowID> = []
    #expect(
      late.restore([window(2, isMinimized: true)], into: &rows, floated: &floated).restored.isEmpty)
    #expect(late.restore([window(2)], into: &rows, floated: &floated).restored == [WindowID(2)])
    #expect(windows(rows, 0) == [1, 2, 3])
  }

  @Test func aFloatedWindowIsFloatedAgain() {
    var (rows, late) = takenOver([1, 2, 3, 4])
    var floated: Set<WindowID> = []
    #expect(late.restore([window(5)], into: &rows, floated: &floated).restored == [WindowID(5)])
    #expect(floated == [WindowID(5)])
    #expect(late.isEmpty)
  }

  @Test func aWindowAlreadyOnAWorkspaceStaysThereAndIsPutBackOnlyOnce() {
    var (rows, late) = takenOver([1, 3, 4])
    rows[0][1].insert(WindowID(2))
    var floated: Set<WindowID> = []
    #expect(late.restore([window(2)], into: &rows, floated: &floated).restored.isEmpty)
    #expect(windows(rows, 1) == [4, 2])
    rows[0][1].remove(WindowID(2))
    #expect(late.restore([window(2)], into: &rows, floated: &floated).restored.isEmpty)
    #expect(windows(rows, 0) == [1, 3])
  }

  @Test func anotherAppsWindowWithAHandedOverIDIsANewWindow() {
    var state = saved
    state.apps = [SavedState.WindowApp(id: WindowID(2), processID: 1)]
    let taken: Set<WindowID> = [WindowID(1), WindowID(3), WindowID(4)]
    var rows = state.rows(count: 3) { taken.contains($0) }
    var late = LateHandOver(state, taken: taken)
    var floated: Set<WindowID> = []
    let stranger = late.restore([window(2, processID: 7)], into: &rows, floated: &floated)
    #expect(stranger == LateHandOver.Outcome())
    #expect(late.restore([window(2)], into: &rows, floated: &floated).restored.isEmpty)
    #expect(windows(rows, 0) == [1, 3])
  }
}
