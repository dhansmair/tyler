import CoreGraphics
import Testing
import TylerCore
import TylerTestSupport

@testable import TylerServer

/// Windows 1 and 2 on the primary display, and what the mover remembers while moving them.
@Suite("WindowMover")
@MainActor
struct WindowMoverTests {
  private let backend = FakeWindowSystem(windows: spread([1, 2]))
  private let displays = FakeDisplays(displays: [FakeDisplays.main, FakeDisplays.right])
  private let mover: WindowMover
  private var registry = WindowRegistry()

  init() {
    mover = WindowMover(backend: backend, displays: displays)
    registry.replaceAll(backend.windows)
  }

  private func originalFrame(_ index: Int) -> CGRect { ManagerHarness.originalFrame(index: index) }

  private var onTheRightDisplay: CGRect {
    CGRect(origin: FakeDisplays.right.visibleFrame.origin, size: CGSize(width: 400, height: 300))
  }

  @Test func theFirstMoveRemembersWhereAWindowWas() {
    mover.place(
      [Placement(id: WindowID(1), frame: .init(x: 100, y: 100, width: 50, height: 50))],
      known: registry)
    mover.nudge(WindowID(2), to: CGPoint(x: 70, y: 70), known: registry)
    mover.place(
      [Placement(id: WindowID(1), frame: .init(x: 200, y: 100, width: 50, height: 50))],
      known: registry)
    #expect(mover.originalFrames == [WindowID(1): originalFrame(0), WindowID(2): originalFrame(1)])
  }

  @Test func aWindowTheUserCarriesIsNotRemembered() {
    mover.carry(WindowID(1), to: CGPoint(x: 70, y: 70), known: registry)
    mover.carry(WindowID(2), toFrame: CGRect(x: 0, y: 0, width: 90, height: 90), known: registry)
    #expect(backend.nudges.map(\.id) == [WindowID(1)])
    #expect(backend.moves.map(\.id) == [WindowID(2)])
    #expect(mover.originalFrames.isEmpty)
  }

  @Test func aWindowSentToAnotherDisplayIsCrossingUntilLetGo() {
    mover.place([Placement(id: WindowID(1), frame: onTheRightDisplay)], known: registry)
    mover.place([Placement(id: WindowID(2), frame: originalFrame(1))], known: registry)
    #expect(mover.crossing == [WindowID(1)])
    mover.release([WindowID(2)])
    #expect(mover.crossing == [WindowID(1)])
    mover.letGoOfCrossings()
    #expect(mover.crossing.isEmpty)
  }

  @Test func forgettingAWindowClearsEverythingKeptAboutIt() throws {
    for windowID in [WindowID(1), WindowID(2)] {
      mover.place([Placement(id: windowID, frame: onTheRightDisplay)], known: registry)
      try mover.focus(windowID, known: registry)
    }
    mover.forget(WindowID(1))
    #expect(mover.originalFrames == [WindowID(2): originalFrame(1)])
    #expect(mover.crossing == [WindowID(2)])
  }

  @Test func takingOverKeepsOnlyWindowsThatStillExist() {
    let frame = CGRect(x: 10, y: 20, width: 300, height: 200)
    let saved = SavedState(
      row: WorkspaceRow(count: 2), floated: [], tilingEnabled: true,
      originalFrames: [WindowID(1): frame, WindowID(2): frame], seen: [])
    mover.adopt(saved, known: [WindowID(2), WindowID(3)])
    #expect(mover.originalFrames == [WindowID(2): frame])
  }

  @Test func aClosedWindowIsForgottenByTheMoverToo() async throws {
    let harness = ManagerHarness([1, 2])
    try harness.manager.requestFocus(WindowID(2))
    #expect(harness.manager.mover.originalFrames[WindowID(2)] != nil)
    #expect(harness.manager.interpreter.expectedFocus == [WindowID(2)])
    harness.backend.send(.destroyed(WindowID(2)))
    await harness.settle()
    #expect(harness.manager.mover.originalFrames[WindowID(2)] == nil)
    #expect(harness.manager.interpreter.expectedFocus.isEmpty)
  }
}
