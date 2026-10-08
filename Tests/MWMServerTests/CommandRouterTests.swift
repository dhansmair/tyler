import MWMCore
import Testing

@testable import MWMServer

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
}
