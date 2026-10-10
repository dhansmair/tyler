import CoreGraphics
import Testing
import TylerCore

@testable import TylerServer

@Suite("Workspaces: the configured count")
@MainActor
struct WorkspaceCountTests {
  private func config(count: Int) -> Config {
    Config(workspaces: Config.Workspaces(count: count))
  }

  @Test func theCountComesFromTheConfig() {
    let harness = ManagerHarness([1], config: config(count: 6))
    #expect(harness.manager.switchWorkspace(.number(6)) == .message("workspace 6"))
    #expect(
      harness.manager.switchWorkspace(.number(7))
        == .error("workspace 7 does not exist (use 1 to 6)"))
  }

  @Test func reloadAddsWorkspaces() {
    let file = FakeConfigFile()
    let harness = ManagerHarness([1], configFile: file)
    file.write(.config(config(count: 6)))

    #expect(harness.manager.reload() == .message("reloaded \(FakeConfigFile.path)"))
    #expect(harness.manager.switchWorkspace(.number(6)) == .message("workspace 6"))
  }

  @Test func reloadMergesRemovedWorkspacesIntoTheLastAndBringsThemIntoView() async {
    let file = FakeConfigFile()
    let harness = ManagerHarness([1, 2, 3], configFile: file)
    // Window 3 to workspace 4, window 2 to workspace 2; workspace 2 is on screen.
    await harness.osFocus(3)
    _ = harness.manager.moveToWorkspace(.number(4), follow: false)
    await harness.osFocus(2)
    _ = harness.manager.moveToWorkspace(.number(2), follow: true)
    await harness.settle()
    #expect(harness.isParked(3))

    file.write(.config(config(count: 2)))
    #expect(harness.manager.reload() == .message("reloaded \(FakeConfigFile.path)"))
    #expect(harness.workspaces() == [1: 1, 2: 2, 3: 2])
    #expect(!harness.isParked(3), "the merged window joined the workspace on screen")
    #expect(harness.isParked(1), "workspace 1 is still parked")
    let halves = TallLayout().frames(count: 2, in: harness.area, parameters: LayoutParameters())
    #expect([harness.frame(of: 2), harness.frame(of: 3)] == halves)
  }

  @Test func reloadRemovingTheCurrentWorkspaceShowsTheNewLastOne() async {
    let file = FakeConfigFile()
    let harness = ManagerHarness([1, 2], configFile: file)
    await harness.osFocus(2)
    _ = harness.manager.moveToWorkspace(.number(4), follow: true)
    await harness.settle()

    file.write(.config(config(count: 1)))
    harness.manager.reload()
    #expect(harness.workspaces() == [1: 1, 2: 1])
    #expect(!harness.isParked(1))
    #expect(!harness.isParked(2))
    #expect(harness.manager.switchWorkspace(.next) == .message("workspace 1"))
  }

  @Test func aRestartWithFewerWorkspacesShowsTheMergedWindows() async {
    let harness = ManagerHarness([1, 2])
    await harness.osFocus(2)
    _ = harness.manager.moveToWorkspace(.number(3), follow: false)
    await harness.settle()
    #expect(harness.isParked(2))
    let saved = harness.manager.handOver()

    let backend = FakeBackend(windows: harness.backend.windows)
    let successor = WindowManager(
      backend: backend, displays: FakeDisplays(), gate: FakeGate(isTrusted: true),
      config: config(count: 1), restoring: saved)
    successor.startIfPermitted()
    let halves = TallLayout().frames(count: 2, in: harness.area, parameters: LayoutParameters())
    #expect(
      [1, 2].map { id in backend.windows.first { $0.id == WindowID(id) }?.frame } == halves,
      "window 2 was merged into workspace 1, the one on screen, and came out of parking")
  }
}
