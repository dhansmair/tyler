import CoreGraphics
import Testing
import TylerCore
import TylerTestSupport

@testable import TylerServer

/// Where a placement left a window, until its app reports it there.
@Suite("WindowMover: unreported placements")
@MainActor
struct WindowMoverUnreportedTests {
  private let windowSystem = FakeWindowSystem(windows: spread([1, 2]))
  private let clock = TestClock()
  private let mover: WindowMover
  private var registry = WindowRegistry()
  private let placed = CGRect(x: 100, y: 100, width: 400, height: 300)

  init() {
    mover = WindowMover(windowSystem: windowSystem, displays: FakeDisplays(), clock: clock)
    registry.replaceAll(windowSystem.windows)
  }

  private func report(_ windowID: UInt32, at frame: CGRect) {
    var window = registry.window(withID: WindowID(windowID)) ?? makeWindow(id: windowID)
    window.frame = frame
    mover.windowUpdated(window)
  }

  @Test func aPlacementIsWaitedForUntilTheAppReportsIt() {
    mover.place([Placement(id: WindowID(1), frame: placed)], known: registry)
    #expect(mover.unreportedFrames == [WindowID(1): placed])
    report(1, at: placed)
    #expect(mover.unreportedFrames.isEmpty)
  }

  @Test func aReportOfAnEarlierStepKeepsWaiting() {
    mover.place([Placement(id: WindowID(1), frame: placed)], known: registry)
    report(1, at: placed.offsetBy(dx: -40, dy: 0))
    #expect(mover.unreportedFrames == [WindowID(1): placed])
  }

  @Test func afterTheWaitTheRegistryWinsAgain() {
    mover.place([Placement(id: WindowID(1), frame: placed)], known: registry)
    clock.advance(by: WindowMover.reportWait)
    #expect(mover.unreportedFrames.isEmpty)
  }

  @Test func aWindowTheUserCarriesIsNotWaitedFor() {
    mover.carry(WindowID(1), toFrame: placed, known: registry)
    mover.nudge(WindowID(2), to: placed.origin, known: registry)
    #expect(mover.unreportedFrames.isEmpty)
  }

  @Test func aClosedWindowIsForgotten() {
    mover.place([Placement(id: WindowID(1), frame: placed)], known: registry)
    mover.forget(WindowID(1))
    #expect(mover.unreportedFrames.isEmpty)
  }
}
