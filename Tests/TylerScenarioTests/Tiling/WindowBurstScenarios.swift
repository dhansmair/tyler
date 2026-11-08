import CoreGraphics
import Testing
import TylerConfig
import TylerCore
import TylerTestSupport

@testable import TylerServer

/// Windows change one after another, each with its own event, before the apps report tylerd's
/// moves. A window that one change moves and the next puts back would stay where the first put
/// it, if the second compared against frames from before the first: the app's late report of
/// that move is a move, not a list change, and triggers no reconcile (#121).
///
/// Here window 3 closes and window 4 opens, as a splash screen giving way to the app's window.
/// Window 2, the focused one, grows into the closed one's slot and gives it back to the new one.
@Suite("Tiling: windows changing in quick succession")
@MainActor
struct WindowBurstScenarios {
  private let slots: [Region] = [.leftHalf, .rightTop, .rightBottom]

  /// Sends the events without letting tylerd handle them, as they queue behind each other.
  private func closeWithoutWaiting(_ window: UInt32, in scenario: Scenario) {
    scenario.windowSystem.windows.removeAll { $0.id.rawValue == window }
    scenario.windowSystem.send(.destroyed(WindowID(window)))
  }

  private func openWithoutWaiting(_ window: UInt32, in scenario: Scenario) {
    scenario.windowSystem.windows.append(makeWindow(id: window))
    scenario.windowSystem.send(.created(makeWindow(id: window)))
  }

  @Test func aWindowReplacedAtOnceLeavesEveryWindowInItsSlot() async {
    let scenario = await Scenario(workspaces: [1: [1, 2, 3]])
    await scenario.focus(2)
    closeWithoutWaiting(3, in: scenario)
    openWithoutWaiting(4, in: scenario)
    await scenario.runUntilQuiet()
    #expect(scenario.list(1) == [1, 2, 4])
    #expect([1, 2, 4].map(scenario.frame(of:)) == slots.map { scenario.rect($0) })
  }

  @Test func aWindowReplacedWhileTheOthersSlideLeavesEveryWindowInItsSlot() async {
    var config = Config()
    config.animations.retile = 250
    let scenario = await Scenario(workspaces: [1: [1, 2, 3]], config: config, animates: true)
    await scenario.focus(2)
    closeWithoutWaiting(3, in: scenario)
    await scenario.wait(.milliseconds(100))
    openWithoutWaiting(4, in: scenario)
    await scenario.runUntilQuiet()
    #expect(scenario.list(1) == [1, 2, 4])
    #expect([1, 2, 4].map(scenario.frame(of:)) == slots.map { scenario.rect($0) })
  }
}
