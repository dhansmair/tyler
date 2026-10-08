import CoreGraphics
import MWMCore
import Testing

@testable import MWMServer

@Suite("WindowManager")
@MainActor
struct WindowManagerTests {
  private func makeManager(
    backend: FakeBackend = FakeBackend(),
    displays: FakeDisplays = FakeDisplays(),
    gate: FakeGate = FakeGate(isTrusted: true)
  ) -> WindowManager {
    WindowManager(backend: backend, displays: displays, gate: gate)
  }

  private func listedWindows(_ manager: WindowManager) -> [WindowInfo]? {
    guard case .windows(let windows) = manager.windows() else { return nil }
    return windows
  }

  /// Lets the manager's event-pump task run until it has seen what was sent.
  private func settle() async {
    for _ in 0..<20 { await Task.yield() }
  }

  @Test func withoutPermissionItWaitsAndExplains() {
    let backend = FakeBackend()
    let manager = makeManager(backend: backend, gate: FakeGate(isTrusted: false))

    #expect(manager.startIfPermitted() == false)
    #expect(manager.state == .waitingForPermission)
    #expect(backend.startCount == 0)
    #expect(manager.windows() == .error(WindowManager.permissionMessage))
  }

  @Test func startsOnceAndLoadsTheInitialSnapshot() {
    let backend = FakeBackend(windows: [makeWindow(id: 1), makeWindow(id: 2)])
    let manager = makeManager(backend: backend)

    #expect(manager.startIfPermitted())
    #expect(manager.state == .running)
    #expect(backend.startCount == 1)
    #expect(listedWindows(manager)?.map(\.id.rawValue) == [1, 2])

    #expect(manager.startIfPermitted())
    #expect(backend.startCount == 1, "a second call must not restart the backend")
  }

  @Test func startsLaterOnceThePermissionIsGranted() {
    let gate = FakeGate(isTrusted: false)
    let backend = FakeBackend(windows: [makeWindow(id: 1)])
    let manager = makeManager(backend: backend, gate: gate)

    #expect(manager.startIfPermitted() == false)
    gate.isTrusted = true
    #expect(manager.startIfPermitted())
    #expect(listedWindows(manager)?.count == 1)
  }

  @Test func backendEventsChangeTheList() async {
    let backend = FakeBackend()
    let manager = makeManager(backend: backend)
    manager.startIfPermitted()

    backend.send(.created(makeWindow(id: 1, title: "a")))
    backend.send(.created(makeWindow(id: 2, title: "b")))
    backend.send(.updated(makeWindow(id: 1, title: "a2")))
    backend.send(.focused(WindowID(2)))
    backend.send(.destroyed(WindowID(1)))
    await settle()

    let windows = listedWindows(manager)
    #expect(windows?.map(\.id.rawValue) == [2])
    #expect(windows?.first?.isFocused == true)
  }

  @Test func eventsSentBeforeTheSnapshotAreNotDuplicated() async {
    // The backend reports a window both in its snapshot and as a created event.
    let backend = FakeBackend(windows: [makeWindow(id: 1)])
    let manager = makeManager(backend: backend)
    backend.send(.created(makeWindow(id: 1)))
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
    let backend = FakeBackend(windows: [
      makeWindow(id: 1, frame: CGRect(x: 100, y: 100, width: 300, height: 200)),
      makeWindow(id: 2, frame: CGRect(x: 1200, y: 100, width: 300, height: 200)),
    ])
    let manager = makeManager(backend: backend, displays: FakeDisplays(displays: [left, right]))
    manager.startIfPermitted()

    #expect(listedWindows(manager)?.map(\.displayID) == [10, 20])
  }

  @Test func withoutAnyDisplayTheTagIsNil() {
    let backend = FakeBackend(windows: [makeWindow(id: 1)])
    let manager = makeManager(backend: backend, displays: FakeDisplays(displays: []))
    manager.startIfPermitted()
    #expect(listedWindows(manager)?.first?.displayID == nil)
  }

  @Test func stopClearsStateAndStopsTheBackend() {
    let backend = FakeBackend(windows: [makeWindow(id: 1)])
    let manager = makeManager(backend: backend)
    manager.startIfPermitted()

    manager.stop()
    #expect(backend.stopCount == 1)
    #expect(manager.state == .waitingForPermission)
    #expect(manager.windows() == .error(WindowManager.permissionMessage))
  }

  @Test func theBackendStreamEndingLeavesTheLastKnownList() async {
    let backend = FakeBackend(windows: [makeWindow(id: 1)])
    let manager = makeManager(backend: backend)
    manager.startIfPermitted()

    backend.finish()
    await settle()
    #expect(listedWindows(manager)?.count == 1)
  }
}
