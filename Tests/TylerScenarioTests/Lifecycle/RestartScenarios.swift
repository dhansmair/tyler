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
  private func arranged(
    animates: Bool = false, slide: Duration = Animator.defaultDuration,
    frameInterval: Duration = Animator.defaultFrameInterval
  ) async -> Scenario {
    let scenario = await Scenario(
      openAtStart: spread([1, 2, 3]), animates: animates, slide: slide,
      frameInterval: frameInterval)
    await scenario.focus(3)
    await scenario.command("window move-to-workspace next")
    await scenario.command("layout set full")
    scenario.windowSystem.clearRecordedCalls()
    return scenario
  }

  /// `id` as `scenario`'s tylerd last saw it, to appear again for the next one.
  private func window(_ id: UInt32, of scenario: Scenario) -> WindowInfo {
    guard let window = scenario.windowSystem.windows.first(where: { $0.id == WindowID(id) })
    else {
      Issue.record("no window \(id)")
      return makeWindow(id: id)
    }
    return window
  }

  private func isFloated(_ id: UInt32, in scenario: Scenario) -> Bool {
    scenario.windowList.first { $0.id == WindowID(id) }?.isFloated == true
  }

  @Test func handingOverMovesNoWindow() async {
    let scenario = await arranged()
    let frames = scenario.windowSystem.windows.map(\.frame)
    let next = await scenario.restart()
    #expect(next.workspaces == [1: 1, 2: 1, 3: 2], "the workspaces were handed over")
    #expect(scenario.windowSystem.moves.isEmpty)
    #expect(scenario.windowSystem.windows.map(\.frame) == frames)
    #expect(scenario.windowSystem.stopCount == 1)
  }

  @Test func theNextTylerdCarriesOnWithoutMovingAnything() async {
    let next = await arranged().restart()
    #expect(next.workspaces == [1: 1, 2: 1, 3: 2])
    #expect(next.windowSystem.moves.isEmpty, "every window is already where it belongs")
    #expect(await next.command("layout next") == .message("layout tall"), "the layout survived")
  }

  // A state file from before several displays can't be written through a Scenario.
  @Test func aStateFromATylerdBeforeSeveralDisplaysIsTakenOver() async {
    let harness = ManagerHarness([1, 2, 3])
    await harness.osFocus(3)
    _ = harness.manager.moveToWorkspace(.next, follow: false)
    _ = harness.manager.setLayout(.set(.full))
    await harness.settle()
    harness.windowSystem.clearRecordedCalls()
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
    let next = await arranged().restart(closing: [1])
    #expect(next.workspaces == [2: 1, 3: 2])
  }

  @Test func theOriginalFramesSurviveSoStopStillUndoesEverything() async {
    let next = await arranged().restart()
    await next.stop()
    let frames = next.windowSystem.windows.sorted { $0.id < $1.id }.map(\.frame)
    #expect(frames == (0..<3).map(ManagerHarness.originalFrame(index:)))
  }

  @Test func theNextTylerdTilesTheHandedOverWorkspacesWithItsGaps() async {
    let gaps = Config(gaps: Config.Gaps(inner: 8, outer: 12))
    let next = await arranged().restart(config: gaps)
    #expect(await next.command("workspace focus next") == .message("workspace 2"))
    let expected = TallLayout().frames(
      count: 1, in: FakeDisplays.main.visibleFrame,
      gaps: LayoutGaps(inner: 8, outer: 12))
    #expect(next.frame(of: 3) == expected.first)
  }

  @Test func floatedWindowsAndTilingOffSurvive() async {
    let scenario = await Scenario(openAtStart: spread([1, 2]))
    await scenario.focus(2)
    await scenario.command("window float toggle")
    await scenario.command("tiling off")
    let next = await scenario.restart()
    #expect(next.tiling == .off)
    await next.command("tiling on")
    #expect(isFloated(2, in: next))
  }

  @Test func aSlideInProgressIsFinishedBeforeHandingOver() async {
    let scenario = await arranged(
      animates: true, slide: .milliseconds(48), frameInterval: .milliseconds(16))
    await scenario.start("workspace focus next")
    await scenario.wait(.milliseconds(16))
    let next = await scenario.restart()
    #expect(scenario.isParked(1))
    #expect(scenario.isParked(2))
    #expect(next.shown == [2])
  }

  // Only the state itself shows every part of it passed on unchanged.
  @Test func beforePermissionTheHandedOverStateIsPassedOn() {
    let saved = SavedState(
      row: WorkspaceRow(), floated: [], tilingEnabled: false, originalFrames: [:])
    let harness = ManagerHarness(
      windows: [], gate: FakeGate(isTrusted: false), restoring: saved)
    #expect(harness.manager.handOver() == saved)
  }

  @Test func aWindowWhoseAppAnswersLateGetsItsWorkspaceBack() async {
    let scenario = await arranged()
    let next = await scenario.restart(closing: [3])
    #expect(next.workspaces == [1: 1, 2: 1])
    await next.open(window(3, of: scenario))
    #expect(next.workspaces == [1: 1, 2: 1, 3: 2])
    #expect(next.isParked(3))
    #expect(next.windowSystem.moves.isEmpty)
    await next.stop()
    #expect(next.frame(of: 3) == ManagerHarness.originalFrame(index: 2), "stop puts it back")
  }

  @Test func aRestartOnALockedScreenGetsEveryWorkspaceBackAsTheWindowsAppear() async {
    let scenario = await arranged()
    let next = await scenario.restart(closing: [1, 2, 3])
    for id: UInt32 in [2, 3, 1] {
      await next.open(window(id, of: scenario))
    }
    #expect(next.workspaces == [1: 1, 2: 1, 3: 2])
    #expect(next.list(1) == [1, 2])
    #expect(next.windowSystem.moves.isEmpty, "every window is already where it belongs")
    #expect(await next.command("layout next") == .message("layout tall"), "the layout survived")
  }

  @Test func aFloatedWindowThatAppearsLateIsStillFloated() async {
    let scenario = await Scenario(openAtStart: spread([1, 2]))
    await scenario.focus(2)
    await scenario.command("window float toggle")
    let next = await scenario.restart(closing: [2])
    await next.open(window(2, of: scenario))
    #expect(next.workspaces == [1: 1])
    #expect(isFloated(2, in: next))
  }
}
