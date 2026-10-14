import CoreGraphics
import Testing
import TylerConfig
import TylerCore
import TylerTestSupport

@testable import TylerServer

@Suite("Layouts: the default of new workspaces")
@MainActor
struct DefaultLayoutScenarios {
  private func config(_ initial: LayoutKind, count: Int = 4) -> Config {
    Config(
      layouts: Config.Layouts(initial: initial), workspaces: Config.Workspaces(count: count))
  }

  private func layouts(_ harness: ManagerHarness) -> [LayoutKind] {
    harness.manager.workspaces.workspaces.map(\.layout)
  }

  @Test func everyWorkspaceStartsWithTheDefault() {
    let harness = ManagerHarness([1, 2], config: config(.full))
    #expect(layouts(harness) == [.full, .full, .full, .full])
    #expect(harness.frame(of: 1) == harness.area)
    #expect(harness.frame(of: 2) == harness.area)
  }

  @Test func withoutAConfigWorkspacesStartTall() {
    #expect(layouts(ManagerHarness([1])) == [.tall, .tall, .tall, .tall])
  }

  @Test func workspacesAddedByReloadGetTheNewDefault() {
    let file = FakeConfigFile()
    let harness = ManagerHarness([1], configFile: file)
    _ = harness.manager.setLayout(.set(.full))
    file.write(.config(config(.strip, count: 5)))
    _ = harness.manager.reload()
    // Workspaces that existed keep their layout; only the new one gets the new default.
    #expect(layouts(harness) == [.full, .tall, .tall, .tall, .strip])
  }

  @Test func aHandOverKeepsEachWorkspacesLayout() {
    let harness = ManagerHarness([1], config: config(.full))
    _ = harness.manager.setLayout(.set(.tall))
    let successor = harness.successor(saved: harness.manager.handOver(), config: config(.strip))
    #expect(layouts(successor) == [.tall, .full, .full, .full])
  }
}
