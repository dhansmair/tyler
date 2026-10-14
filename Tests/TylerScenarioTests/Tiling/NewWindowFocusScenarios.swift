import CoreGraphics
import Testing
import TylerCore
import TylerTestSupport

@testable import TylerServer

/// Tiling: a new window that macOS focused before tylerd could tile it is the one the commands
/// act on.
@Suite("Tiling: focus of a new window")
@MainActor
struct NewWindowFocusScenarios {
  @Test func swapMovesANewWindowFocusedBeforeItWasCreated() async {
    let scenario = await Scenario(workspaces: [1: [1, 2]])
    scenario.harness.windowSystem.send(.focused(WindowID(3)))
    scenario.harness.windowSystem.send(.created(makeWindow(id: 3)))
    await scenario.runUntilQuiet()
    #expect(scenario.list(1) == [1, 3, 2])

    await scenario.command("window swap next")

    #expect(scenario.list(1) == [1, 2, 3])
  }

  @Test func swapMovesANewWindowFocusedBeforeItWasTileable() async {
    let scenario = await Scenario(workspaces: [1: [1, 2]])
    scenario.harness.windowSystem.send(.created(makeWindow(id: 3, kind: .dialog)))
    scenario.harness.windowSystem.send(.focused(WindowID(3)))
    scenario.harness.windowSystem.send(.updated(makeWindow(id: 3)))
    await scenario.runUntilQuiet()
    #expect(scenario.list(1) == [1, 3, 2])

    await scenario.command("window swap next")

    #expect(scenario.list(1) == [1, 2, 3])
  }
}
