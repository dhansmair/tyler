import CoreGraphics
import Testing
import TylerCore
import TylerProtocol
import TylerTestSupport

/// `tyler debug windows`: tylerd's list against a fresh read of the windows.
@Suite("debug windows")
@MainActor
struct DebugWindowsScenarios {
  private func reportedDrift(in scenario: Scenario) async -> WindowDrift? {
    guard case .drift(let drift) = await scenario.command("debug windows") else { return nil }
    return drift
  }

  @Test func inStepThereAreNoDifferences() async throws {
    let scenario = await Scenario(workspaces: [1: [1, 2, 3]])
    let drift = try #require(await reportedDrift(in: scenario))
    #expect(drift.isEmpty)
    #expect(drift.checkedCount == 3)
  }

  @Test func aMissedMinimizeShowsAndNothingMoves() async throws {
    let scenario = await Scenario(workspaces: [1: [1, 2, 3]])
    scenario.windowSystem.clearRecordedCalls()
    // The app minimizes window 2 without telling tylerd.
    let index = try #require(scenario.windowSystem.windows.firstIndex { $0.id.rawValue == 2 })
    scenario.windowSystem.windows[index].isMinimized = true
    let drift = try #require(await reportedDrift(in: scenario))
    #expect(drift.differences.map(\.field) == [.minimized])
    #expect(drift.differences.first?.id == WindowID(2))
    #expect(scenario.windowSystem.moves.isEmpty)
    #expect(scenario.list(1) == [1, 2, 3], "it reports, it doesn't fix")
  }

  @Test func whatOnlyMacOSHasIsPassedOn() async throws {
    let scenario = await Scenario(workspaces: [1: [1]])
    scenario.windowSystem.untracked = [makeWindow(id: 9)]
    scenario.windowSystem.unattachedApps = ["Busy"]
    let drift = try #require(await reportedDrift(in: scenario))
    #expect(drift.untracked.map(\.id) == [WindowID(9)])
    #expect(drift.unattachedApps == ["Busy"])
  }

  @Test func aWorkspaceFocusOtherThanMacOSsShows() async throws {
    let scenario = await Scenario(workspaces: [1: [1, 2, 3]])
    await scenario.focus(1)
    #expect(try #require(await reportedDrift(in: scenario)).isEmpty)
    // The fake window system doesn't report the focus back, so macOS still has window 1 focused.
    await scenario.command("window focus next")
    let drift = try #require(await reportedDrift(in: scenario))
    #expect(drift.differences.map(\.field) == [.workspaceFocus])
    #expect(drift.differences.first?.believed == "2")
    #expect(drift.differences.first?.actual == "1")
  }

  @Test func aFocusTylerdMissedShowsBesideItsWorkspaceFocus() async throws {
    let scenario = await Scenario(workspaces: [1: [1, 2, 3]])
    await scenario.focus(1)
    scenario.windowSystem.freshFocus = WindowID(3)
    let drift = try #require(await reportedDrift(in: scenario))
    #expect(drift.differences.map(\.field) == [.focus, .workspaceFocus])
    #expect(drift.differences.map(\.id) == [WindowID(3), WindowID(3)])
    #expect(drift.differences.map(\.believed) == ["1", "1"])
  }
}
