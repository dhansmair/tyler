import CoreGraphics
import Testing
import TylerConfig
import TylerCore
import TylerTestSupport

@testable import TylerServer

@Suite("Restart: handing over the workspaces")
@MainActor
struct RestartScenarios {
  /// Windows 1 and 2 on workspace 1 in the full layout, window 3 parked on workspace 2, and
  /// workspace 1 on screen.
  private func arranged(animator: Animator = .snap) async -> ManagerHarness {
    let harness = ManagerHarness([1, 2, 3], animator: animator)
    await harness.osFocus(3)
    _ = harness.manager.moveToWorkspace(.next, follow: false)
    _ = harness.manager.setLayout(.set(.full))
    await harness.settle()
    harness.windowSystem.clearRecordedCalls()
    return harness
  }

  @Test func handingOverMovesNoWindow() async {
    let harness = await arranged()
    let frames = harness.windowSystem.windows.map(\.frame)
    #expect(harness.manager.handOver() != nil)
    #expect(harness.windowSystem.moves.isEmpty)
    #expect(harness.windowSystem.windows.map(\.frame) == frames)
    #expect(harness.windowSystem.stopCount == 1)
  }

  @Test func theNextTylerdCarriesOnWithoutMovingAnything() async {
    let harness = await arranged()
    let successor = harness.successor(saved: harness.manager.handOver())
    #expect(successor.workspaces() == [1: 1, 2: 1, 3: 2])
    #expect(successor.windowSystem.moves.isEmpty, "every window is already where it belongs")
    #expect(successor.manager.setLayout(.next) == .message("layout tall"), "the layout survived")
  }

  @Test func aStateFromATylerdBeforeSeveralDisplaysIsTakenOver() async {
    let harness = await arranged()
    let row = harness.manager.workspaces
    let old = SavedState(
      row: row, floated: [], tilingEnabled: true, originalFrames: [:],
      seen: [WindowID(1), WindowID(2), WindowID(3)])
    _ = harness.manager.handOver()
    let successor = harness.successor(saved: old)
    #expect(successor.manager.workspaces == row)
    #expect(successor.windowSystem.moves.isEmpty)
  }

  @Test func windowsThatClosedInBetweenAreLeftOut() async {
    let harness = await arranged()
    let successor = harness.successor(saved: harness.manager.handOver(), closing: [1])
    #expect(successor.workspaces() == [2: 1, 3: 2])
  }

  @Test func theOriginalFramesSurviveSoStopStillUndoesEverything() async {
    let harness = await arranged()
    let successor = harness.successor(saved: harness.manager.handOver())
    successor.manager.stop()
    let frames = successor.windowSystem.windows.sorted { $0.id < $1.id }.map(\.frame)
    #expect(frames == (0..<3).map(ManagerHarness.originalFrame(index:)))
  }

  @Test func theNextTylerdTilesTheHandedOverWorkspacesWithItsGaps() async {
    let harness = await arranged()
    let gaps = Config(gaps: Config.Gaps(inner: 8, outer: 12))
    let successor = harness.successor(saved: harness.manager.handOver(), config: gaps)
    #expect(successor.manager.switchWorkspace(.next) == .message("workspace 2"))
    await settle()
    let expected = TallLayout().frames(
      count: 1, in: FakeDisplays.main.visibleFrame,
      gaps: LayoutGaps(inner: 8, outer: 12))
    #expect(successor.windowSystem.frame(of: 3) == expected.first)
  }

  @Test func floatedWindowsAndTilingOffSurvive() async {
    let harness = ManagerHarness([1, 2])
    await harness.osFocus(2)
    _ = harness.manager.setFloat(.toggle)
    _ = harness.manager.setTiling(.off)
    let successor = harness.successor(saved: harness.manager.handOver())
    #expect(successor.manager.tilingStatus == .off)
    _ = successor.manager.setTiling(.on)
    guard case .windows(let windows) = successor.manager.windows() else {
      Issue.record("no windows")
      return
    }
    #expect(windows.first { $0.id == WindowID(2) }?.isFloated == true)
  }

  @Test func aFloatedWindowGoesBackToItsPlaceAfterARestart() async {
    let harness = ManagerHarness([1, 2, 3])
    await harness.osFocus(1)
    _ = harness.manager.setFloat(.on)
    let successor = harness.successor(saved: harness.manager.handOver())
    await successor.osFocus(1)
    _ = successor.manager.setFloat(.off)
    #expect(successor.manager.rows.focused.current.windows.first == WindowID(1))
  }

  @Test func aSlideInProgressIsFinishedBeforeHandingOver() async {
    let clock = TestClock()
    let animator = Animator(
      duration: .milliseconds(48), frameInterval: .milliseconds(16), clock: clock)
    let harness = await arranged(animator: animator)
    _ = harness.manager.switchWorkspace(.next)
    clock.advance(by: .milliseconds(16))
    await harness.settle()
    let saved = harness.manager.handOver()
    #expect(harness.isParked(1))
    #expect(harness.isParked(2))
    #expect(saved?.displays?.first?.currentIndex == 1)
  }

  @Test func beforePermissionTheHandedOverStateIsPassedOn() {
    let saved = SavedState(
      row: WorkspaceRow(), floated: [], tilingEnabled: false, originalFrames: [:])
    let harness = ManagerHarness(
      windows: [], gate: FakeGate(isTrusted: false), restoring: saved)
    #expect(harness.manager.handOver() == saved)
  }

  /// The windows of `windows` named in `ids` appear one by one, as apps that answer late do.
  private func appear(_ ids: [UInt32], of windows: [WindowInfo], in next: ManagerHarness) async {
    for id in ids {
      guard let window = windows.first(where: { $0.id == WindowID(id) }) else { continue }
      next.windowSystem.windows.append(window)
      next.windowSystem.send(.created(window))
      await next.settle()
    }
  }

  @Test func aWindowWhoseAppAnswersLateGetsItsWorkspaceBack() async {
    let harness = await arranged()
    let windows = harness.windowSystem.windows
    let successor = harness.successor(saved: harness.manager.handOver(), closing: [3])
    #expect(successor.workspaces() == [1: 1, 2: 1])
    await appear([3], of: windows, in: successor)
    #expect(successor.workspaces() == [1: 1, 2: 1, 3: 2])
    #expect(successor.isParked(3))
    #expect(successor.windowSystem.moves.isEmpty)
    successor.manager.stop()
    #expect(successor.frame(of: 3) == ManagerHarness.originalFrame(index: 2), "stop puts it back")
  }

  @Test func aRestartOnALockedScreenGetsEveryWorkspaceBackAsTheWindowsAppear() async {
    let harness = await arranged()
    let windows = harness.windowSystem.windows
    let successor = harness.successor(saved: harness.manager.handOver(), closing: [1, 2, 3])
    await appear([2, 3, 1], of: windows, in: successor)
    #expect(successor.workspaces() == [1: 1, 2: 1, 3: 2])
    #expect(successor.manager.workspaces[0].windows == [WindowID(1), WindowID(2)])
    #expect(successor.windowSystem.moves.isEmpty, "every window is already where it belongs")
    #expect(successor.manager.setLayout(.next) == .message("layout tall"), "the layout survived")
  }

  @Test func aFloatedWindowThatAppearsLateIsStillFloated() async {
    let harness = ManagerHarness([1, 2])
    await harness.osFocus(2)
    _ = harness.manager.setFloat(.toggle)
    let windows = harness.windowSystem.windows
    let successor = harness.successor(saved: harness.manager.handOver(), closing: [2])
    await appear([2], of: windows, in: successor)
    #expect(successor.workspaces() == [1: 1])
    guard case .windows(let listed) = successor.manager.windows() else {
      Issue.record("no windows")
      return
    }
    #expect(listed.first { $0.id == WindowID(2) }?.isFloated == true)
  }
}
