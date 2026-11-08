import CoreGraphics
import Testing
import TylerCore
import TylerTestSupport

@testable import TylerServer

/// A floated window that leaves every workspace stays floated, and floats again on the workspace
/// it comes back to. Workspace 1 holds window 1, tiled, and window 2, floated.
@Suite("Tiling: floated windows off their workspace")
@MainActor
struct FloatKeptScenarios {
  private func isFloated(_ id: UInt32, in scenario: Scenario) -> Bool {
    scenario.windowList.first { $0.id == WindowID(id) }?.isFloated == true
  }

  private func scenario() async -> Scenario {
    let scenario = await Scenario(workspaces: [1: [1, 2], 2: [3]])
    await scenario.focus(2)
    await scenario.command("window float on")
    return scenario
  }

  @Test func aMinimizedFloatedWindowFloatsAgainWhenRestored() async {
    let scenario = await scenario()
    await scenario.change(makeWindow(id: 2, isMinimized: true))
    #expect(scenario.workspaces[2] == nil)
    #expect(isFloated(2, in: scenario))
    await scenario.command("workspace focus next")
    await scenario.change(makeWindow(id: 2))
    #expect(scenario.workspaces[2] == 2, "the current workspace")
    #expect(isFloated(2, in: scenario))
    #expect(scenario.list(2) == [3])
  }

  @Test func aFloatedWindowOnAParkedWorkspaceStaysFloatedThroughTilingOffAndOn() async {
    let scenario = await scenario()
    await scenario.command("workspace focus next")
    await scenario.command("tiling off")
    #expect(isFloated(2, in: scenario))
    await scenario.command("tiling on")
    #expect(isFloated(2, in: scenario))
    #expect(scenario.workspaces[2] == 2, "on the current workspace, as every other window")
    #expect(!scenario.list(2).contains(2))
  }
}
