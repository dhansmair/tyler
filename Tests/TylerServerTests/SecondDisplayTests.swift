import CoreGraphics
import Testing
import TylerCore

@testable import TylerServer

/// With a second display connected, everything still happens on the primary one: its area, its
/// parking spot, its slides and its resizing. These pin what M5's refactor must keep for windows
/// on the primary display.
@Suite("Two displays: the primary display's workspaces")
@MainActor
struct SecondDisplayTests {
  private let pointer = FakePointer()
  private let clock = TestClock()

  private func twoDisplays() -> FakeDisplays {
    FakeDisplays(displays: [FakeDisplays.main, FakeDisplays.secondary])
  }

  @Test func theIndicatorShowsThePrimaryDisplaysArea() {
    let indicator = FakeIndicator()
    let manager = WindowManager(
      backend: FakeBackend(windows: spread([1, 2])), displays: twoDisplays(),
      gate: FakeGate(isTrusted: true), indicator: indicator)
    manager.startIfPermitted()
    #expect(indicator.shown.last?.area == FakeDisplays.main.visibleFrame)
  }

  @Test func aWindowOpeningOnAnotherWorkspaceParksAtThePrimaryDisplaysEdge() async {
    let harness = ManagerHarness(
      [1], displays: twoDisplays(), config: Config(assignments: ["firefox": 3]))
    var firefox = makeWindow(id: 9, frame: CGRect(x: 700, y: 100, width: 300, height: 200))
    firefox.appName = "Firefox"
    harness.backend.windows.append(firefox)
    harness.backend.send(.created(firefox))
    await harness.settle()

    #expect(harness.workspaces()[9] == 3)
    #expect(harness.frame(of: 9)?.minX == FakeDisplays.main.visibleFrame.maxX - 1)
  }

  @Test func aSwipeSlidesThePrimaryDisplaysWorkspaces() async {
    let harness = ManagerHarness([1, 2], displays: twoDisplays(), pointer: pointer, clock: clock)
    await harness.osFocus(2)
    _ = harness.manager.moveToWorkspace(.number(2), follow: false)
    await harness.settle()

    for update in [PanUpdate.began, .moved(offset: -0.18), .ended(velocity: 0)] {
      pointer.pan(update)
    }
    await harness.settle()
    #expect(harness.manager.workspaces.currentIndex == 1)
    #expect(harness.frame(of: 2) == FakeDisplays.main.visibleFrame)
    #expect(harness.frame(of: 1)?.minX == FakeDisplays.main.visibleFrame.maxX - 1)
  }

  @Test func resizingWithTheMouseLaysOutInThePrimaryDisplaysArea() async {
    let harness = ManagerHarness(
      [1, 2, 3], displays: twoDisplays(), pointer: pointer, clock: clock)
    await harness.settle()

    pointer.isPrimaryButtonDown = true
    await harness.backend.userMoves(1, to: CGRect(x: 55, y: 38, width: 1047, height: 1131))
    #expect(harness.frame(of: 2) == CGRect(x: 1102, y: 38, width: 698, height: 566))
    pointer.release()
    await harness.settle()
    #expect(harness.frame(of: 3) == CGRect(x: 1102, y: 604, width: 698, height: 565))
  }
}
