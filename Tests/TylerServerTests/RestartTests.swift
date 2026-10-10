import CoreGraphics
import Testing
import TylerCore

@testable import TylerServer

@Suite("Restart: handing over the workspaces")
@MainActor
struct RestartTests {
  /// A second tylerd that finds the windows exactly where the first one left them.
  @MainActor
  private struct Successor {
    let manager: WindowManager
    let backend: FakeBackend

    init(after first: WorkspaceHarness, saved: SavedState?, closing closed: [UInt32] = []) {
      let windows = first.backend.windows.filter { !closed.contains($0.id.rawValue) }
      backend = FakeBackend(windows: windows)
      manager = WindowManager(
        backend: backend, displays: FakeDisplays(), gate: FakeGate(isTrusted: true),
        restoring: saved)
      manager.startIfPermitted()
    }

    func workspaces() -> [UInt32: Int] {
      guard case .windows(let windows) = manager.windows() else { return [:] }
      return Dictionary(
        uniqueKeysWithValues: windows.compactMap { window in
          window.workspace.map { (window.id.rawValue, $0) }
        })
    }
  }

  /// Windows 1 and 2 on workspace 1 in the full layout, window 3 parked on workspace 2, and
  /// workspace 1 on screen.
  private func arranged(animator: Animator = .snap) async -> WorkspaceHarness {
    let harness = WorkspaceHarness([1, 2, 3], animator: animator)
    await harness.osFocus(3)
    _ = harness.manager.moveToWorkspace(.down, follow: false)
    _ = harness.manager.setLayout(.set(.full))
    await harness.settle()
    harness.backend.clearRecordedCalls()
    return harness
  }

  @Test func handingOverMovesNoWindow() async {
    let harness = await arranged()
    let frames = harness.backend.windows.map(\.frame)
    #expect(harness.manager.handOver() != nil)
    #expect(harness.backend.moves.isEmpty)
    #expect(harness.backend.windows.map(\.frame) == frames)
    #expect(harness.backend.stopCount == 1)
  }

  @Test func theNextTylerdCarriesOnWithoutMovingAnything() async {
    let harness = await arranged()
    let successor = Successor(after: harness, saved: harness.manager.handOver())
    #expect(successor.workspaces() == [1: 1, 2: 1, 3: 2])
    #expect(successor.backend.moves.isEmpty, "every window is already where it belongs")
    #expect(successor.manager.setLayout(.next) == .message("layout tall"), "the layout survived")
  }

  @Test func windowsThatClosedInBetweenAreLeftOut() async {
    let harness = await arranged()
    let successor = Successor(after: harness, saved: harness.manager.handOver(), closing: [1])
    #expect(successor.workspaces() == [2: 1, 3: 2])
  }

  @Test func theOriginalFramesSurviveSoStopStillUndoesEverything() async {
    let harness = await arranged()
    let successor = Successor(after: harness, saved: harness.manager.handOver())
    successor.manager.stop()
    let frames = successor.backend.windows.sorted { $0.id < $1.id }.map(\.frame)
    #expect(frames == (0..<3).map(WorkspaceHarness.originalFrame(index:)))
  }

  @Test func floatedWindowsAndTilingOffSurvive() async {
    let harness = WorkspaceHarness([1, 2])
    await harness.osFocus(2)
    _ = harness.manager.toggleFloat()
    _ = harness.manager.setTiling(.off)
    let successor = Successor(after: harness, saved: harness.manager.handOver())
    #expect(successor.manager.tilingStatus == .off)
    _ = successor.manager.setTiling(.on)
    guard case .windows(let windows) = successor.manager.windows() else {
      Issue.record("no windows")
      return
    }
    #expect(windows.first { $0.id == WindowID(2) }?.isFloated == true)
  }

  @Test func aSlideInProgressIsFinishedBeforeHandingOver() async {
    let clock = TestClock()
    let animator = Animator(
      duration: .milliseconds(48), frameInterval: .milliseconds(16), clock: clock)
    let harness = await arranged(animator: animator)
    _ = harness.manager.switchWorkspace(.down)
    clock.advance(by: .milliseconds(16))
    await harness.settle()
    let saved = harness.manager.handOver()
    #expect(harness.isParked(1))
    #expect(harness.isParked(2))
    #expect(saved?.currentIndex == 1)
  }

  @Test func beforePermissionTheHandedOverStateIsPassedOn() {
    let saved = SavedState(
      stack: WorkspaceStack(), floated: [], tilingEnabled: false, originalFrames: [:])
    let manager = WindowManager(
      backend: FakeBackend(), displays: FakeDisplays(), gate: FakeGate(isTrusted: false),
      restoring: saved)
    #expect(manager.handOver() == saved)
  }
}
