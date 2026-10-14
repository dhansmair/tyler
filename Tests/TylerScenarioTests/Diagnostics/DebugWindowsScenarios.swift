import CoreGraphics
import Testing
import TylerCore
import TylerTestSupport

@testable import TylerServer

/// `tyler debug windows`: tylerd's list against a fresh read of the windows.
@Suite("debug windows")
@MainActor
struct DebugWindowsScenarios {
  private func reportedDrift(in harness: ManagerHarness) -> WindowDrift? {
    guard case .drift(let drift) = harness.manager.handle(.debugWindows) else { return nil }
    return drift
  }

  @Test func inStepThereAreNoDifferences() async throws {
    let harness = ManagerHarness([1, 2, 3])
    await harness.settle()
    let drift = try #require(reportedDrift(in: harness))
    #expect(drift.isEmpty)
    #expect(drift.checkedCount == 3)
  }

  @Test func aMissedMinimizeShowsAndNothingMoves() async throws {
    let harness = ManagerHarness([1, 2, 3])
    await harness.settle()
    harness.backend.clearRecordedCalls()
    // The app minimizes window 2 without telling tylerd.
    harness.backend.windows[1].isMinimized = true
    let drift = try #require(reportedDrift(in: harness))
    #expect(drift.differences.map(\.field) == [.minimized])
    #expect(drift.differences.first?.id == WindowID(2))
    #expect(harness.backend.moves.isEmpty)
    #expect(harness.manager.slots[2] == 2, "it reports, it doesn't fix")
  }

  @Test func whatOnlyMacOSHasIsPassedOn() async throws {
    let harness = ManagerHarness([1])
    await harness.settle()
    harness.backend.untracked = [makeWindow(id: 9)]
    harness.backend.unattachedApps = ["Busy"]
    let drift = try #require(reportedDrift(in: harness))
    #expect(drift.untracked.map(\.id) == [WindowID(9)])
    #expect(drift.unattachedApps == ["Busy"])
  }
}
