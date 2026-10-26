import CoreGraphics
import Testing
import TylerCore
import TylerTestSupport

@testable import TylerServer

/// A restart onto a tylerd under another grant (an ad-hoc build, the bare tylerd and the app):
/// the old one puts every window back and still hands its workspaces over, so nothing waits
/// parked while the new one has no grant, and it tiles them again once it has.
@Suite("Restart onto another grant: windows back, workspaces handed over")
@MainActor
struct RestartOntoAnotherGrantScenarios {
  /// Windows 1 and 2 on workspace 1 in the full layout, window 3 parked on workspace 2, and
  /// workspace 1 on screen.
  private func arranged() async -> Scenario {
    let scenario = await Scenario(openAtStart: spread([1, 2, 3]))
    await scenario.focus(3)
    await scenario.command("window move-to-workspace next")
    await scenario.command("layout set full")
    scenario.windowSystem.clearRecordedCalls()
    return scenario
  }

  private var originalFrames: [CGRect] { (0..<3).map(ManagerHarness.originalFrame(index:)) }

  private var slot: CGRect? {
    TallLayout().frames(count: 1, in: FakeDisplays.main.visibleFrame, gaps: LayoutGaps()).first
  }

  private func frames(_ scenario: Scenario) -> [CGRect] {
    scenario.windowSystem.windows.sorted { $0.id < $1.id }.map(\.frame)
  }

  @Test func everyWindowGoesBackWhereItWasParkedOnesIncluded() async {
    let scenario = await arranged()
    #expect(scenario.isParked(3))
    let next = await scenario.restart(puttingWindowsBack: true)
    #expect(next.workspaces == [1: 1, 2: 1, 3: 2], "the workspaces were still handed over")
    #expect(frames(scenario) == originalFrames)
    #expect(scenario.windowSystem.stopCount == 1)
  }

  /// The new tylerd waits for its grant with every window in view, then tiles the handed-over
  /// workspaces: the windows are back in their slots and window 3 parked on workspace 2.
  @Test func theNextTylerdTilesThemAgainOnceItHasItsGrant() async {
    let scenario = await arranged()
    let tiled = frames(scenario)
    let next = await scenario.restart(puttingWindowsBack: true, gate: FakeGate(isTrusted: false))
    #expect(next.tiling == .waitingForPermission)
    #expect(frames(next) == originalFrames, "nothing moves without the grant")

    await next.grantPermission()
    #expect(next.workspaces == [1: 1, 2: 1, 3: 2])
    #expect(Array(frames(next).prefix(2)) == Array(tiled.prefix(2)))
    #expect(next.isParked(3), "parked with the size it was put back with")

    #expect(await next.command("workspace focus next") == .message("workspace 2"))
    #expect(next.frame(of: 3) == slot)
  }

  /// Window 3 started on the laptop and was sent to the display above it. Put back, it is on the
  /// laptop again, but its workspace is on the other display: it stays on that workspace, and goes
  /// back to that display, rather than joining the laptop's.
  @Test func aWindowPutBackOnAnotherDisplayThanItsWorkspacesKeepsItsWorkspace() async {
    let scenario = await Scenario(
      openAtStart: spread([1, 2, 3]), displays: [FakeDisplays.main, FakeDisplays.secondary])
    await scenario.focus(3)
    #expect(
      await scenario.command("window move-to-display next") == .message("moved to display 2"))
    #expect(scenario.workspaces == [1: 1, 2: 1, 3: 5])
    let next = await scenario.restart(puttingWindowsBack: true, gate: FakeGate(isTrusted: false))
    #expect(frames(scenario) == originalFrames, "window 3 is back on the laptop")

    await next.grantPermission()
    #expect(next.workspaces == [1: 1, 2: 1, 3: 5])
    let above = FakeDisplays.secondary.frame
    #expect(above.intersects(next.frame(of: 3) ?? .zero), "back on the display above")
  }

  /// All in view while the new tylerd waits for its grant, a window may be minimized meanwhile:
  /// it leaves its workspace, and the others are laid out once, without it.
  @Test func aWindowMinimizedWhileWaitingIsLeftOutAndNotMoved() async {
    let scenario = await arranged()
    let next = await scenario.restart(puttingWindowsBack: true, gate: FakeGate(isTrusted: false))
    guard var minimized = next.windowSystem.windows.first(where: { $0.id == WindowID(2) }) else {
      Issue.record("no window 2")
      return
    }
    minimized.isMinimized = true
    await next.change(minimized)
    await next.grantPermission()
    #expect(next.workspaces == [1: 1, 3: 2])
    #expect(!next.windowSystem.moves.contains { $0.id == WindowID(2) })
    // Laid out once, without window 2: window 1 goes straight to the whole of its workspace.
    let firstMoves = next.windowSystem.moves.filter { $0.id == WindowID(1) }.map(\.frame)
    #expect(!firstMoves.isEmpty && firstMoves.allSatisfy { $0 == slot })
  }

  @Test func stopStillPutsEveryWindowBackAfterwards() async {
    let next = await arranged().restart(puttingWindowsBack: true)
    await next.stop()
    #expect(frames(next) == originalFrames)
  }
}
