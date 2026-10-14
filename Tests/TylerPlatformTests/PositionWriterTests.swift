import ApplicationServices
import Dispatch
import Foundation
import Testing
import TylerCore
import TylerServer

@testable import TylerPlatform

/// Real queues, with the write held at a semaphore where a test needs a move under way. An
/// application element stands in for the window: the fake write never touches it.
@Suite("PositionWriter")
@MainActor
struct PositionWriterTests {
  /// The moves written, and a gate the first move of window 1 waits at until it opens.
  private final class Apps: @unchecked Sendable {
    // Guarded by `lock`; the semaphores are safe from any thread.
    private let lock = NSLock()
    private var log: [String] = []
    private var isHolding = true
    let gate = DispatchSemaphore(value: 0)
    let entered = DispatchSemaphore(value: 0)

    var written: [String] { lock.withLock { log } }

    func write(_ windowID: WindowID, _ move: PositionWriter.Move) {
      let holds = lock.withLock { () -> Bool in
        defer { if windowID == WindowID(1) { isHolding = false } }
        return isHolding && windowID == WindowID(1)
      }
      if holds {
        entered.signal()
        gate.wait()
      }
      lock.withLock { log.append("\(windowID.rawValue)@\(Int(move.origin.x))") }
    }
  }

  private let element = AXUIElementCreateApplication(1)

  private func makeWriter(_ apps: Apps) -> PositionWriter {
    PositionWriter(write: { windowID, move in apps.write(windowID, move) })
  }

  private func openSoon(_ gate: DispatchSemaphore) {
    DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(30)) { gate.signal() }
  }

  @Test func settlingWaitsForTheMoveUnderWayAndDropsTheOneWaiting() throws {
    let apps = Apps()
    let writer = makeWriter(apps)
    try writer.move(WindowID(1), element, to: CGPoint(x: 10, y: 0), in: 100)
    apps.entered.wait()
    try writer.move(WindowID(1), element, to: CGPoint(x: 20, y: 0), in: 100)
    try writer.move(WindowID(2), element, to: CGPoint(x: 30, y: 0), in: 100)
    openSoon(apps.gate)

    try writer.settle(WindowID(1), in: 100)
    #expect(apps.written == ["1@10", "2@30"], "1@20 was dropped; the app's other window landed")
  }

  @Test func anAppDoesNotWaitForAnother() throws {
    let apps = Apps()
    let writer = makeWriter(apps)
    try writer.move(WindowID(1), element, to: CGPoint(x: 10, y: 0), in: 100)
    apps.entered.wait()
    try writer.move(WindowID(2), element, to: CGPoint(x: 30, y: 0), in: 200)
    try writer.settle(WindowID(3), in: 200)
    #expect(apps.written == ["2@30"], "app 100 is still held")

    apps.gate.signal()
    try writer.settle(WindowID(1), in: 100)
    #expect(apps.written == ["2@30", "1@10"])
  }

  @Test func settlingAnAppWithoutMovesReturnsAtOnce() throws {
    let writer = makeWriter(Apps())
    try writer.settle(WindowID(1), in: 100)
  }

  @Test func statisticsAddUpEveryApp() throws {
    let apps = Apps()
    let writer = makeWriter(apps)
    try writer.move(WindowID(1), element, to: CGPoint(x: 10, y: 0), in: 100)
    apps.entered.wait()
    try writer.move(WindowID(1), element, to: CGPoint(x: 20, y: 0), in: 100)
    try writer.move(WindowID(1), element, to: CGPoint(x: 25, y: 0), in: 100)
    try writer.move(WindowID(2), element, to: CGPoint(x: 30, y: 0), in: 200)
    apps.gate.signal()
    try writer.settle(WindowID(3), in: 100)
    try writer.settle(WindowID(3), in: 200)
    let statistics = writer.takeStatistics()
    #expect(statistics.written == 3)
    #expect(statistics.skipped == 1)
  }

  @Test func anAppThatTimedOutIsLeftAloneForThePause() throws {
    final class Now { var instant = ContinuousClock.now }
    let now = Now()
    let apps = Apps()
    let writer = PositionWriter(
      now: { now.instant }, write: { windowID, move in apps.write(windowID, move) })
    writer.noteTimeout(of: 100)

    #expect(throws: BackendError.self) {
      try writer.move(WindowID(2), element, to: CGPoint(x: 20, y: 0), in: 100)
    }
    #expect(throws: BackendError.self) { try writer.settle(WindowID(2), in: 100) }
    try writer.move(WindowID(3), element, to: CGPoint(x: 30, y: 0), in: 200)
    try writer.settle(WindowID(4), in: 200)
    #expect(apps.written == ["3@30"], "another app is still moved")

    now.instant += UnresponsiveApps.pause
    try writer.move(WindowID(2), element, to: CGPoint(x: 25, y: 0), in: 100)
    try writer.settle(WindowID(4), in: 100)
    #expect(apps.written == ["3@30", "2@25"])
  }
}
