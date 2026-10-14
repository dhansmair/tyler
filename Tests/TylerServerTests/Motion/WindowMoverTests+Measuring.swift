import CoreGraphics
import Testing
import TylerCore
import TylerTestSupport

@testable import TylerServer

/// What the mover adds up while a slide, swipe or drag is measured.
@Suite("WindowMover: measuring")
@MainActor
struct WindowMoverMeasuringTests {
  private let backend = FakeBackend(windows: spread([1, 2]))
  private let clock = TestClock()
  private let mover: WindowMover
  private var registry = WindowRegistry()

  init() {
    mover = WindowMover(backend: backend, displays: FakeDisplays(), clock: clock)
    registry.replaceAll(backend.windows)
  }

  @Test func everyWriteIsCountedWhileMeasuring() {
    mover.nudge(WindowID(1), to: CGPoint(x: 10, y: 10), known: registry)
    mover.startMeasuring()
    mover.nudge(WindowID(1), to: CGPoint(x: 20, y: 10), known: registry)
    mover.place(
      [Placement(id: WindowID(2), frame: CGRect(x: 0, y: 0, width: 90, height: 90))],
      known: registry)
    mover.carry(WindowID(1), to: CGPoint(x: 30, y: 10), known: registry)
    mover.carry(WindowID(2), toFrame: CGRect(x: 0, y: 0, width: 80, height: 80), known: registry)
    mover.windowUpdated()
    let cost = mover.stopMeasuring()
    #expect(cost?.writes == 4)
    #expect(cost?.updates == 1)
  }

  @Test func framesAreTimedOnTheClock() {
    mover.startMeasuring()
    mover.frameStarted()
    clock.advance(by: .milliseconds(8))
    mover.frameStarted()
    clock.advance(by: .milliseconds(21))
    mover.frameStarted()
    let cost = mover.stopMeasuring()
    #expect(cost?.frames == 3)
    #expect(cost?.longestFrameGap == .milliseconds(21))
  }

  @Test func nothingIsKeptOutsideAMeasurement() {
    mover.frameStarted()
    mover.windowUpdated()
    #expect(mover.stopMeasuring() == nil)
    mover.startMeasuring()
    #expect(mover.stopMeasuring() == MotionCost())
    #expect(mover.stopMeasuring() == nil, "stopping ends the measurement")
  }
}
