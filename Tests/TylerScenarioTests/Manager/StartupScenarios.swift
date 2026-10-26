import CoreGraphics
import Testing
import TylerCore
import TylerTestSupport

@testable import TylerServer

@Suite("Starting and stopping")
@MainActor
struct StartupScenarios {
  private func listed(_ scenario: Scenario) async -> [WindowInfo]? {
    guard case .windows(let windows) = await scenario.command("window list") else { return nil }
    return windows
  }

  @Test func withoutPermissionItWaitsAndExplains() async {
    let scenario = await Scenario(openAtStart: [], gate: FakeGate(isTrusted: false))

    #expect(scenario.tiling == .waitingForPermission)
    #expect(scenario.windowSystem.startCount == 0)
    #expect(await scenario.command("window list") == .error(WindowManager.permissionMessage))
  }

  @Test func startsOnceAndLoadsTheInitialSnapshot() async {
    let scenario = await Scenario(openAtStart: [makeWindow(id: 1), makeWindow(id: 2)])

    #expect(scenario.tiling == .on)
    #expect(scenario.windowSystem.startCount == 1)
    #expect(await listed(scenario)?.map(\.id.rawValue) == [1, 2])

    await scenario.grantPermission()
    #expect(
      scenario.windowSystem.startCount == 1,
      "finding the permission again must not restart the window system")
  }

  @Test func startsLaterOnceThePermissionIsGranted() async {
    let scenario = await Scenario(
      openAtStart: [makeWindow(id: 1)], gate: FakeGate(isTrusted: false))
    await scenario.grantPermission()
    #expect(scenario.tiling == .on)
    #expect(await listed(scenario)?.count == 1)
  }

  @Test func windowEventsChangeTheList() async {
    let scenario = await Scenario(openAtStart: [])

    await scenario.open(makeWindow(id: 1, title: "a"))
    await scenario.open(makeWindow(id: 2, title: "b"))
    await scenario.change(makeWindow(id: 1, title: "a2"))
    await scenario.focus(2)
    await scenario.close(1)

    let windows = await listed(scenario)
    #expect(windows?.map(\.id.rawValue) == [2])
    #expect(windows?.first?.isFocused == true)
  }

  @Test func eventsSentBeforeTheSnapshotAreNotDuplicated() async {
    let scenario = await Scenario(
      openAtStart: [makeWindow(id: 1)], gate: FakeGate(isTrusted: false))
    // The window system reports a window both in its snapshot and as a created event.
    scenario.windowSystem.send(.created(makeWindow(id: 1)))
    await scenario.grantPermission()

    #expect(await listed(scenario)?.count == 1)
  }

  @Test func windowsAreTaggedWithTheirDisplay() async {
    let left = DisplayInfo(
      id: 10,
      frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
      visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800)
    )
    let right = DisplayInfo(
      id: 20,
      frame: CGRect(x: 1000, y: 0, width: 1000, height: 800),
      visibleFrame: CGRect(x: 1000, y: 0, width: 1000, height: 800)
    )
    let scenario = await Scenario(
      openAtStart: [
        makeWindow(id: 1, frame: CGRect(x: 100, y: 100, width: 300, height: 200)),
        makeWindow(id: 2, frame: CGRect(x: 1200, y: 100, width: 300, height: 200)),
      ],
      displays: [left, right])

    #expect(await listed(scenario)?.map(\.displayID) == [10, 20])
  }

  @Test func withoutAnyDisplayTheTagIsNil() async {
    let scenario = await Scenario(openAtStart: [makeWindow(id: 1)], displays: [])
    #expect(await listed(scenario)?.first?.displayID == nil)
  }

  @Test func stopClearsStateAndStopsTheWindowSystem() async {
    let scenario = await Scenario(openAtStart: [makeWindow(id: 1)])

    await scenario.stop()
    #expect(scenario.windowSystem.stopCount == 1)
    #expect(scenario.tiling == .waitingForPermission)
    #expect(await scenario.command("window list") == .error(WindowManager.permissionMessage))
  }

  @Test func theWindowSystemsEventsEndingLeavesTheLastKnownList() async {
    let scenario = await Scenario(openAtStart: [makeWindow(id: 1)])

    scenario.windowSystem.finish()
    await scenario.runUntilQuiet()
    #expect(await listed(scenario)?.count == 1)
  }

  // tylerd's main follows the permission on its own clock, which would never be quiet inside a
  // Scenario, so these drive the manager.
  @Test func startingSaysWhetherTylerdRuns() {
    let gate = FakeGate(isTrusted: false)
    let manager = WindowManager(
      windowSystem: FakeWindowSystem(windows: spread([1])), displays: FakeDisplays(), gate: gate)
    #expect(manager.startIfPermitted() == false)
    gate.isTrusted = true
    #expect(manager.startIfPermitted())
    #expect(manager.startIfPermitted(), "already running")
  }

  @Test func itStartsOnceThePermissionIsGranted() async {
    let gate = FakeGate(isTrusted: false)
    let clock = TestClock()
    let manager = WindowManager(
      windowSystem: FakeWindowSystem(windows: spread([1])), displays: FakeDisplays(), gate: gate,
      clock: clock)
    let starts = Starts()
    let following = Task {
      await manager.followPermission(checkingEvery: .seconds(1)) { starts.count += 1 }
    }
    await settle()
    clock.advance(by: .seconds(1))
    await settle()
    #expect(manager.state == .waitingForPermission)
    gate.isTrusted = true
    clock.advance(by: .seconds(1))
    await settle()
    #expect(manager.state == .running)
    #expect(starts.count == 1)
    following.cancel()
    await following.value
  }

  @Test func followingThePermissionEndsWhenCancelled() async {
    let clock = TestClock()
    let manager = WindowManager(
      windowSystem: FakeWindowSystem(), displays: FakeDisplays(), gate: FakeGate(isTrusted: false),
      clock: clock)
    let following = Task { await manager.followPermission {} }
    await settle()
    following.cancel()
    await following.value
    #expect(manager.state == .waitingForPermission)
  }

  @MainActor
  private final class Starts {
    var count = 0
  }
}
