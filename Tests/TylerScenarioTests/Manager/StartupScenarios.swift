import CoreGraphics
import Testing
import TylerCore
import TylerTestSupport

@testable import TylerServer

@Suite("WindowManager")
@MainActor
struct StartupScenarios {
  private func makeManager(
    windowSystem: FakeWindowSystem = FakeWindowSystem(),
    displays: FakeDisplays = FakeDisplays(),
    gate: FakeGate = FakeGate(isTrusted: true)
  ) -> WindowManager {
    WindowManager(windowSystem: windowSystem, displays: displays, gate: gate)
  }

  private func listedWindows(_ manager: WindowManager) -> [WindowInfo]? {
    guard case .windows(let windows) = manager.windows() else { return nil }
    return windows
  }

  @Test func withoutPermissionItWaitsAndExplains() {
    let windowSystem = FakeWindowSystem()
    let manager = makeManager(windowSystem: windowSystem, gate: FakeGate(isTrusted: false))

    #expect(manager.startIfPermitted() == false)
    #expect(manager.state == .waitingForPermission)
    #expect(windowSystem.startCount == 0)
    #expect(manager.windows() == .error(WindowManager.permissionMessage))
  }

  @Test func startsOnceAndLoadsTheInitialSnapshot() {
    let windowSystem = FakeWindowSystem(windows: [makeWindow(id: 1), makeWindow(id: 2)])
    let manager = makeManager(windowSystem: windowSystem)

    #expect(manager.startIfPermitted())
    #expect(manager.state == .running)
    #expect(windowSystem.startCount == 1)
    #expect(listedWindows(manager)?.map(\.id.rawValue) == [1, 2])

    #expect(manager.startIfPermitted())
    #expect(windowSystem.startCount == 1, "a second call must not restart the window system")
  }

  @Test func startsLaterOnceThePermissionIsGranted() {
    let gate = FakeGate(isTrusted: false)
    let windowSystem = FakeWindowSystem(windows: [makeWindow(id: 1)])
    let manager = makeManager(windowSystem: windowSystem, gate: gate)

    #expect(manager.startIfPermitted() == false)
    gate.isTrusted = true
    #expect(manager.startIfPermitted())
    #expect(listedWindows(manager)?.count == 1)
  }

  @Test func backendEventsChangeTheList() async {
    let windowSystem = FakeWindowSystem()
    let manager = makeManager(windowSystem: windowSystem)
    manager.startIfPermitted()

    windowSystem.send(.created(makeWindow(id: 1, title: "a")))
    windowSystem.send(.created(makeWindow(id: 2, title: "b")))
    windowSystem.send(.updated(makeWindow(id: 1, title: "a2")))
    windowSystem.send(.focused(WindowID(2)))
    windowSystem.send(.destroyed(WindowID(1)))
    await settle()

    let windows = listedWindows(manager)
    #expect(windows?.map(\.id.rawValue) == [2])
    #expect(windows?.first?.isFocused == true)
  }

  @Test func eventsSentBeforeTheSnapshotAreNotDuplicated() async {
    // The window system reports a window both in its snapshot and as a created event.
    let windowSystem = FakeWindowSystem(windows: [makeWindow(id: 1)])
    let manager = makeManager(windowSystem: windowSystem)
    windowSystem.send(.created(makeWindow(id: 1)))
    manager.startIfPermitted()
    await settle()

    #expect(listedWindows(manager)?.count == 1)
  }

  @Test func windowsAreTaggedWithTheirDisplay() {
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
    let windowSystem = FakeWindowSystem(windows: [
      makeWindow(id: 1, frame: CGRect(x: 100, y: 100, width: 300, height: 200)),
      makeWindow(id: 2, frame: CGRect(x: 1200, y: 100, width: 300, height: 200)),
    ])
    let manager = makeManager(
      windowSystem: windowSystem, displays: FakeDisplays(displays: [left, right]))
    manager.startIfPermitted()

    #expect(listedWindows(manager)?.map(\.displayID) == [10, 20])
  }

  @Test func withoutAnyDisplayTheTagIsNil() {
    let windowSystem = FakeWindowSystem(windows: [makeWindow(id: 1)])
    let manager = makeManager(windowSystem: windowSystem, displays: FakeDisplays(displays: []))
    manager.startIfPermitted()
    #expect(listedWindows(manager)?.first?.displayID == nil)
  }

  @Test func stopClearsStateAndStopsTheBackend() {
    let windowSystem = FakeWindowSystem(windows: [makeWindow(id: 1)])
    let manager = makeManager(windowSystem: windowSystem)
    manager.startIfPermitted()

    manager.stop()
    #expect(windowSystem.stopCount == 1)
    #expect(manager.state == .waitingForPermission)
    #expect(manager.windows() == .error(WindowManager.permissionMessage))
  }

  @Test func theBackendStreamEndingLeavesTheLastKnownList() async {
    let windowSystem = FakeWindowSystem(windows: [makeWindow(id: 1)])
    let manager = makeManager(windowSystem: windowSystem)
    manager.startIfPermitted()

    windowSystem.finish()
    await settle()
    #expect(listedWindows(manager)?.count == 1)
  }

  @Test func itStartsOnceThePermissionIsGranted() async {
    let gate = FakeGate(isTrusted: false)
    let clock = TestClock()
    let manager = WindowManager(
      windowSystem: FakeWindowSystem(windows: spread([1])), displays: FakeDisplays(), gate: gate,
      clock: clock)
    let waiting = Task { await manager.startWhenPermitted(checkingEvery: .seconds(1)) }
    await settle()
    clock.advance(by: .seconds(1))
    await settle()
    #expect(manager.state == .waitingForPermission)
    gate.isTrusted = true
    clock.advance(by: .seconds(1))
    #expect(await waiting.value)
    #expect(manager.state == .running)
  }

  @Test func waitingForThePermissionEndsWhenCancelled() async {
    let clock = TestClock()
    let manager = WindowManager(
      windowSystem: FakeWindowSystem(), displays: FakeDisplays(), gate: FakeGate(isTrusted: false),
      clock: clock)
    let waiting = Task { await manager.startWhenPermitted() }
    await settle()
    waiting.cancel()
    #expect(await waiting.value == false)
    #expect(manager.state == .waitingForPermission)
  }
}
