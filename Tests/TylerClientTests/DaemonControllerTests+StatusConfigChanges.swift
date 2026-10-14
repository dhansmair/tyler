import Testing
import TylerCore
import TylerProtocol

@testable import TylerClient

/// `tyler status` names the settings `tyler config set` changed, so a setting that differs from
/// the file can be explained.
@Suite("DaemonController: status and config set")
struct DaemonControllerStatusConfigChangesTests {
  private func report(changes: [String]?) -> Response {
    let system = FakeDaemonSystem()
    system.server = .running(FakeDaemonSystem.status(pid: 77, configChanges: changes))
    return DaemonController(
      system: system, serverPath: FakeDaemonSystem.serverPath, logPath: FakeDaemonSystem.logPath
    ).run(.status)
  }

  @Test func statusListsTheSettingsConfigSetChanged() throws {
    guard case .message(let text) = report(changes: ["gaps.inner", "layouts.default"]) else {
      Issue.record("no message")
      return
    }
    #expect(
      text.contains(
        """
          config  /home/.config/tyler/tyler.toml
                  changed by `config set`: gaps.inner, layouts.default
          tiling  on
        """))
  }

  @Test(arguments: [[], nil] as [[String]?])
  func withoutChangesStatusSaysNothingAboutThem(changes: [String]?) {
    guard case .message(let text) = report(changes: changes) else {
      Issue.record("no message")
      return
    }
    #expect(!text.contains("config set"))
  }
}
