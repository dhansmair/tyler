import Foundation
import Testing
import TylerCore
import TylerProtocol
import TylerTestSupport

@testable import TylerServer

@Suite("CommandRouter")
struct CommandRouterTests {
  @Test func pingAnswersPong() async {
    #expect(await CommandRouter().handle(.ping) == .pong)
  }

  /// The menu bar items send their requests this way, on the main actor.
  @Test @MainActor func aRequestFromTheMainActorTakesTheSamePath() {
    let manager = WindowManager(
      windowSystem: FakeWindowSystem(), displays: FakeDisplays(), gate: FakeGate(isTrusted: true))
    let router = CommandRouter(manager: manager)
    #expect(router.respond(to: .ping) == .pong)
    #expect(router.respond(to: .retile) == manager.handle(.retile))
  }

  @Test func configEditRunsWhatTylerdOpensTheFileWith() async {
    let router = CommandRouter(openConfig: { .message("opened /c.toml") })
    #expect(await router.handle(.configEdit) == .message("opened /c.toml"))
  }

  @Test func configEditWithoutAWayToOpenTheFileIsAnError() async {
    #expect(
      await CommandRouter().handle(.configEdit)
        == .error("opening the config file is not available"))
  }

  @Test func statusWithoutProcessFactsIsAnError() async {
    #expect(await CommandRouter().handle(.status) == .error("status is not available"))
  }

  @Test @MainActor func statusAddsTheTilingStateToTheProcessFacts() async {
    let base = ServerStatus(
      pid: 42, executablePath: "/bin/tylerd", executableModified: nil,
      startedAt: Date(timeIntervalSince1970: 0), configPath: "/c.toml")
    let manager = WindowManager(
      windowSystem: FakeWindowSystem(), displays: FakeDisplays(), gate: FakeGate(isTrusted: true))
    let router = CommandRouter(manager: manager, status: base)

    var expected = base
    expected.tiling = .waitingForPermission
    expected.configChanges = []
    #expect(await router.handle(.status) == .status(expected))

    manager.startIfPermitted()
    expected.tiling = .on
    #expect(await router.handle(.status) == .status(expected))

    _ = manager.setTiling(.off)
    expected.tiling = .off
    #expect(await router.handle(.status) == .status(expected))
  }

  @Test @MainActor func statusAddsWhatConfigSetChanged() async {
    let base = ServerStatus(
      pid: 42, executablePath: "/bin/tylerd", executableModified: nil,
      startedAt: Date(timeIntervalSince1970: 0), configPath: "/c.toml")
    let manager = WindowManager(
      windowSystem: FakeWindowSystem(), displays: FakeDisplays(), gate: FakeGate(isTrusted: true))
    let router = CommandRouter(manager: manager, status: base)
    _ = manager.setConfig("gaps.inner", to: "8")
    guard case .status(let status) = await router.handle(.status) else {
      Issue.record("no status")
      return
    }
    #expect(status.configChanges == ["gaps.inner"])
  }

  @Test func listWithoutAManagerIsAnError() async {
    #expect(await CommandRouter().handle(.list) == .error("window management is not available"))
  }

  @Test @MainActor func listIsAnsweredByTheManager() async {
    let windowSystem = FakeWindowSystem(windows: [makeWindow(id: 1, title: "one")])
    let manager = WindowManager(
      windowSystem: windowSystem,
      displays: FakeDisplays(),
      gate: FakeGate(isTrusted: true)
    )
    manager.startIfPermitted()

    let response = await CommandRouter(manager: manager).handle(.list)
    guard case .windows(let windows) = response else {
      Issue.record("expected windows, got \(response)")
      return
    }
    #expect(windows.map(\.title) == ["one"])
  }

  @Test(arguments: [
    Request.retile, .tiling(.on), .focus(.next), .swap(.next), .layout(.next), .ratio(0.05),
    .float(.toggle), .close,
  ])
  func windowCommandsWithoutAManagerAreAnError(request: Request) async {
    #expect(await CommandRouter().handle(request) == .error("window management is not available"))
  }

  @Test @MainActor func tilingCommandsAreForwardedToTheManager() async {
    let windowSystem = FakeWindowSystem(windows: [makeWindow(id: 1), makeWindow(id: 2)])
    let manager = WindowManager(
      windowSystem: windowSystem, displays: FakeDisplays(), gate: FakeGate(isTrusted: true))
    manager.startIfPermitted()
    let router = CommandRouter(manager: manager)

    #expect(await router.handle(.tiling(.off)) == .message("tiling off"))
    #expect(await router.handle(.retile) == .error(WindowManager.tilingOffMessage))
    #expect(await router.handle(.tiling(.on)) == .message("tiling on"))
    #expect(await router.handle(.layout(.set(.full))) == .message("layout full"))
  }
}
