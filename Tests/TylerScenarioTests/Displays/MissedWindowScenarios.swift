import Testing
import TylerCore
import TylerTestSupport

@testable import TylerServer

/// Windows the window system stopped tracking while they stayed open, as after a wake with a
/// display unplugged: they are found again once the displays settle.
@Suite("Windows missed: found when the displays settle")
@MainActor
struct MissedWindowScenarios {
  /// The window system reports window `id` as gone, but macOS still lists it.
  private func lose(_ id: UInt32, in scenario: Scenario) async {
    let windowSystem = scenario.harness.windowSystem
    windowSystem.untracked = windowSystem.windows.filter { $0.id == WindowID(id) }
    windowSystem.windows.removeAll { $0.id == WindowID(id) }
    windowSystem.send(.destroyed(WindowID(id)))
    await scenario.runUntilQuiet()
  }

  @Test func aMissedWindowIsTiledAgainWhenTheDisplaysSettle() async {
    let scenario = await Scenario(workspaces: [1: [1, 2, 3]])
    await lose(3, in: scenario)
    #expect(scenario.list(1) == [1, 2])

    await scenario.changeDisplays(to: [FakeDisplays.main])
    #expect(scenario.list(1).sorted() == [1, 2, 3])
    #expect(scenario.harness.windowSystem.untracked.isEmpty)
    let slots = [Region.leftHalf, .rightTop, .rightBottom].map { scenario.rect($0) }
    #expect(scenario.list(1).map(scenario.frame(of:)) == slots)
  }
}
