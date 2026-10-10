import Testing
import TylerCore

@testable import TylerServer

@Suite("CommandRouter")
struct CommandRouterTests {
  @Test func pingAnswersPong() async {
    #expect(await CommandRouter().handle(.ping) == .pong)
  }

  @Test func listWithoutAManagerIsAnError() async {
    #expect(await CommandRouter().handle(.list) == .error("window management is not available"))
  }

  @Test @MainActor func listIsAnsweredByTheManager() async {
    let backend = FakeBackend(windows: [makeWindow(id: 1, title: "one")])
    let manager = WindowManager(
      backend: backend,
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
    .toggleFloat,
  ])
  func windowCommandsWithoutAManagerAreAnError(request: Request) async {
    #expect(await CommandRouter().handle(request) == .error("window management is not available"))
  }

  @Test @MainActor func tilingCommandsAreForwardedToTheManager() async {
    let backend = FakeBackend(windows: [makeWindow(id: 1), makeWindow(id: 2)])
    let manager = WindowManager(
      backend: backend, displays: FakeDisplays(), gate: FakeGate(isTrusted: true))
    manager.startIfPermitted()
    let router = CommandRouter(manager: manager)

    #expect(await router.handle(.tiling(.off)) == .message("tiling off"))
    #expect(await router.handle(.retile) == .error(WindowManager.tilingOffMessage))
    #expect(await router.handle(.tiling(.on)) == .message("tiling on"))
    #expect(await router.handle(.layout(.set(.full))) == .message("layout full"))
  }
}
