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
  private func arranged() async -> ManagerHarness {
    let harness = ManagerHarness([1, 2, 3])
    await harness.osFocus(3)
    _ = harness.manager.moveToWorkspace(.next, follow: false)
    _ = harness.manager.setLayout(.set(.full))
    await harness.settle()
    harness.windowSystem.clearRecordedCalls()
    return harness
  }

  private var originalFrames: [CGRect] { (0..<3).map(ManagerHarness.originalFrame(index:)) }

  private func frames(_ harness: ManagerHarness) -> [CGRect] {
    harness.windowSystem.windows.sorted { $0.id < $1.id }.map(\.frame)
  }

  @Test func everyWindowGoesBackWhereItWasParkedOnesIncluded() async {
    let harness = await arranged()
    #expect(harness.isParked(3))
    #expect(harness.manager.handOver(puttingWindowsBack: true) != nil)
    #expect(frames(harness) == originalFrames)
    #expect(harness.windowSystem.stopCount == 1)
  }

  /// The new tylerd waits for its grant with every window in view, then tiles the handed-over
  /// workspaces: the windows are back in their slots and window 3 parked on workspace 2.
  @Test func theNextTylerdTilesThemAgainOnceItHasItsGrant() async {
    let harness = await arranged()
    let tiled = frames(harness)
    let saved = harness.manager.handOver(puttingWindowsBack: true)

    let gate = FakeGate(isTrusted: false)
    let successor = ManagerHarness(
      windows: harness.windowSystem.windows, gate: gate, restoring: saved,
      clearRecordedCalls: false)
    #expect(successor.manager.state == .waitingForPermission)
    #expect(frames(successor) == originalFrames, "nothing moves without the grant")

    gate.isTrusted = true
    #expect(successor.manager.startIfPermitted())
    await successor.settle()
    #expect(successor.workspaces() == [1: 1, 2: 1, 3: 2])
    #expect(Array(frames(successor).prefix(2)) == Array(tiled.prefix(2)))
    #expect(successor.isParked(3), "parked with the size it was put back with")

    #expect(successor.manager.switchWorkspace(.next) == .message("workspace 2"))
    await successor.settle()
    let slot = TallLayout().frames(count: 1, in: successor.area, gaps: LayoutGaps()).first
    #expect(successor.frame(of: 3) == slot)
  }

  /// Window 3 started on the laptop and was sent to the display above it. Put back, it is on the
  /// laptop again, but its workspace is on the other display: it stays on that workspace, and goes
  /// back to that display, rather than joining the laptop's.
  @Test func aWindowPutBackOnAnotherDisplayThanItsWorkspacesKeepsItsWorkspace() async {
    let displays = FakeDisplays(displays: [FakeDisplays.main, FakeDisplays.secondary])
    let harness = ManagerHarness([1, 2, 3], displays: displays)
    await harness.osFocus(3)
    #expect(harness.manager.moveToDisplay(.next, follow: false) == .message("moved to display 2"))
    await harness.settle()
    #expect(harness.workspaces() == [1: 1, 2: 1, 3: 5])
    let saved = harness.manager.handOver(puttingWindowsBack: true)
    #expect(frames(harness) == originalFrames, "window 3 is back on the laptop")

    let gate = FakeGate(isTrusted: false)
    let successor = ManagerHarness(
      windows: harness.windowSystem.windows, displays: displays, gate: gate, restoring: saved,
      clearRecordedCalls: false)
    gate.isTrusted = true
    #expect(successor.manager.startIfPermitted())
    await successor.settle()
    #expect(successor.workspaces() == [1: 1, 2: 1, 3: 5])
    let above = FakeDisplays.secondary.frame
    #expect(above.intersects(successor.frame(of: 3) ?? .zero), "back on the display above")
  }

  /// All in view while the new tylerd waits for its grant, a window may be minimized meanwhile:
  /// it leaves its workspace, and the others are laid out once, without it.
  @Test func aWindowMinimizedWhileWaitingIsLeftOutAndNotMoved() async {
    let harness = await arranged()
    let saved = harness.manager.handOver(puttingWindowsBack: true)
    var windows = harness.windowSystem.windows
    if let index = windows.firstIndex(where: { $0.id == WindowID(2) }) {
      windows[index].isMinimized = true
    }
    let gate = FakeGate(isTrusted: false)
    let successor = ManagerHarness(
      windows: windows, gate: gate, restoring: saved, clearRecordedCalls: false)
    gate.isTrusted = true
    #expect(successor.manager.startIfPermitted())
    await successor.settle()
    #expect(successor.workspaces() == [1: 1, 3: 2])
    #expect(!successor.windowSystem.moves.contains { $0.id == WindowID(2) })
    // Laid out once, without window 2: window 1 goes straight to the whole of its workspace.
    let slot = TallLayout().frames(count: 1, in: successor.area, gaps: LayoutGaps()).first
    let firstMoves = successor.windowSystem.moves.filter { $0.id == WindowID(1) }.map(\.frame)
    #expect(!firstMoves.isEmpty && firstMoves.allSatisfy { $0 == slot })
  }

  @Test func stopStillPutsEveryWindowBackAfterwards() async {
    let harness = await arranged()
    let successor = harness.successor(saved: harness.manager.handOver(puttingWindowsBack: true))
    await successor.settle()
    successor.manager.stop()
    #expect(frames(successor) == originalFrames)
  }
}
