import CoreGraphics
import Testing
import TylerCore

@testable import TylerServer

@Suite("Workspaces: app assignments")
@MainActor
struct AppAssignmentTests {
  /// Firefox goes to workspace 3.
  private let config = Config(assignments: ["firefox": 3])

  private func firefox(id: UInt32, isFocused: Bool = false) -> WindowInfo {
    var window = makeWindow(
      id: id, frame: CGRect(x: 700, y: 100, width: 300, height: 200), isFocused: isFocused)
    window.appName = "Firefox"
    window.bundleID = "org.mozilla.firefox"
    return window
  }

  /// Opens a window the way an app would: it exists, then tylerd hears about it.
  private func open(_ window: WindowInfo, in harness: WorkspaceHarness) async {
    harness.backend.windows.append(window)
    harness.backend.send(.created(window))
    await harness.settle()
  }

  @Test func windowsOpenAtStartGoToTheirWorkspace() {
    let harness = WorkspaceHarness([1, 2], extra: [firefox(id: 9)], config: config)
    #expect(harness.workspaces() == [1: 1, 2: 1, 9: 3])
    #expect(harness.isParked(9))
    let halves = TallLayout().frames(count: 2, in: harness.area, parameters: LayoutParameters())
    #expect([harness.frame(of: 1), harness.frame(of: 2)] == halves)
  }

  @Test func aNewWindowInTheBackgroundIsParkedAndTheViewStays() async {
    let harness = WorkspaceHarness([1, 2], config: config)
    await open(firefox(id: 9), in: harness)

    #expect(harness.workspaces()[9] == 3)
    #expect(harness.isParked(9))
    #expect(harness.backend.moves.map(\.id) == [WindowID(9)], "nothing else moved")
    #expect(harness.manager.switchWorkspace(.number(1)) == .message("workspace 1"))
  }

  @Test func focusingTheNewWindowShowsItsWorkspace() async {
    let harness = WorkspaceHarness([1, 2], config: config)
    await open(firefox(id: 9), in: harness)
    await harness.osFocus(9)

    #expect(!harness.isParked(9))
    #expect(harness.isParked(1))
    #expect(harness.manager.switchWorkspace(.number(3)) == .message("workspace 3"))
  }

  @Test func aNewWindowFocusedBeforeTylerdSeesItShowsItsWorkspace() async {
    let harness = WorkspaceHarness([1, 2], config: config)
    await harness.osFocus(9)
    await open(firefox(id: 9), in: harness)

    #expect(harness.workspaces()[9] == 3)
    #expect(!harness.isParked(9), "the focused window must not be left parked")
    #expect(harness.isParked(1))
  }

  @Test func anAssignmentToTheCurrentWorkspaceTilesAsUsual() async {
    let harness = WorkspaceHarness([1], config: Config(assignments: ["firefox": 1]))
    await open(firefox(id: 9), in: harness)
    #expect(harness.workspaces() == [1: 1, 9: 1])
    #expect(!harness.isParked(9))
  }

  @Test func otherAppsJoinTheCurrentWorkspace() async {
    let harness = WorkspaceHarness([1], config: config)
    await open(
      makeWindow(id: 9, frame: CGRect(x: 700, y: 100, width: 300, height: 200)), in: harness)
    #expect(harness.workspaces() == [1: 1, 9: 1])
  }

  @Test func theBundleIDMatchesToo() async {
    let harness = WorkspaceHarness([1], config: Config(assignments: ["org.mozilla.firefox": 2]))
    await open(firefox(id: 9), in: harness)
    #expect(harness.workspaces()[9] == 2)
  }

  /// Firefox moved by hand to workspace 1 and floated there.
  private func movedAndFloated() async -> WorkspaceHarness {
    let harness = WorkspaceHarness([1], extra: [firefox(id: 9)], config: config)
    await harness.osFocus(9)
    _ = harness.manager.moveToWorkspace(.number(1), follow: true)
    await harness.settle()
    #expect(harness.workspaces()[9] == 1)
    _ = harness.manager.toggleFloat()
    #expect(harness.workspaces()[9] == nil)
    return harness
  }

  @Test func aWindowThatWasTiledBeforeDoesNotJumpBack() async {
    let harness = await movedAndFloated()
    _ = harness.manager.toggleFloat()
    #expect(harness.workspaces()[9] == 1, "un-floated on the current workspace")
  }

  @Test func aRestartRemembersWhichWindowsWereTiled() async {
    let harness = await movedAndFloated()
    let saved = harness.manager.handOver()

    let backend = FakeBackend(windows: harness.backend.windows)
    let successor = WindowManager(
      backend: backend, displays: FakeDisplays(), gate: FakeGate(isTrusted: true),
      config: config, restoring: saved)
    successor.startIfPermitted()
    backend.send(.focused(WindowID(9)))
    for _ in 0..<30 { await Task.yield() }
    _ = successor.toggleFloat()
    guard case .windows(let windows) = successor.windows() else {
      Issue.record("no windows")
      return
    }
    #expect(windows.first { $0.id == WindowID(9) }?.workspace == 1)
  }

  @Test func aClosedWindowsIDIsForgotten() async {
    let harness = await movedAndFloated()
    harness.backend.windows.removeAll { $0.id == WindowID(9) }
    harness.backend.send(.destroyed(WindowID(9)))
    await harness.settle()
    // Window ids can be reused; a new window with this id is new.
    await open(firefox(id: 9), in: harness)
    #expect(harness.workspaces()[9] == 3)
  }
}
