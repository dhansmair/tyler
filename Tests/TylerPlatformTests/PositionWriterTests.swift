import ApplicationServices
import Dispatch
import Foundation
import Testing
import TylerCore

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
    PositionWriter { windowID, move in apps.write(windowID, move) }
  }

  private func openSoon(_ gate: DispatchSemaphore) {
    DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(30)) { gate.signal() }
  }

  @Test func settlingWaitsForTheMoveUnderWayAndDropsTheOneWaiting() {
    let apps = Apps()
    let writer = makeWriter(apps)
    writer.move(WindowID(1), element, to: CGPoint(x: 10, y: 0), in: 100)
    apps.entered.wait()
    writer.move(WindowID(1), element, to: CGPoint(x: 20, y: 0), in: 100)
    writer.move(WindowID(2), element, to: CGPoint(x: 30, y: 0), in: 100)
    openSoon(apps.gate)

    writer.settle(WindowID(1), in: 100)
    #expect(apps.written == ["1@10", "2@30"], "1@20 was dropped; the app's other window landed")
  }

  @Test func anAppDoesNotWaitForAnother() {
    let apps = Apps()
    let writer = makeWriter(apps)
    writer.move(WindowID(1), element, to: CGPoint(x: 10, y: 0), in: 100)
    apps.entered.wait()
    writer.move(WindowID(2), element, to: CGPoint(x: 30, y: 0), in: 200)
    writer.settle(WindowID(3), in: 200)
    #expect(apps.written == ["2@30"], "app 100 is still held")

    apps.gate.signal()
    writer.settle(WindowID(1), in: 100)
    #expect(apps.written == ["2@30", "1@10"])
  }

  @Test func settlingAnAppWithoutMovesReturnsAtOnce() {
    let writer = makeWriter(Apps())
    writer.settle(WindowID(1), in: 100)
  }

  @Test func statisticsAddUpEveryApp() {
    let apps = Apps()
    let writer = makeWriter(apps)
    writer.move(WindowID(1), element, to: CGPoint(x: 10, y: 0), in: 100)
    apps.entered.wait()
    writer.move(WindowID(1), element, to: CGPoint(x: 20, y: 0), in: 100)
    writer.move(WindowID(1), element, to: CGPoint(x: 25, y: 0), in: 100)
    writer.move(WindowID(2), element, to: CGPoint(x: 30, y: 0), in: 200)
    apps.gate.signal()
    writer.settle(WindowID(3), in: 100)
    writer.settle(WindowID(3), in: 200)
    let statistics = writer.takeStatistics()
    #expect(statistics.written == 3)
    #expect(statistics.skipped == 1)
  }
}
