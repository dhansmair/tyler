import Dispatch
import Foundation
import Testing

@testable import TylerPlatform

/// The queue's writes are held at a semaphore where a test needs them to wait, so what is still
/// pending is known exactly.
@Suite("AppWriteQueue")
struct AppWriteQueueTests {
  /// The writes so far, and a gate the first write waits at until the test opens it.
  private final class Writer: @unchecked Sendable {
    // Guarded by `lock`; the gate is a semaphore, safe from any thread.
    private let lock = NSLock()
    private var log: [String] = []
    let gate = DispatchSemaphore(value: 0)
    let entered = DispatchSemaphore(value: 0)
    var holdsFirstWrite = true

    var written: [String] { lock.withLock { log } }

    func write(_ key: Int, _ item: String) {
      let holds = lock.withLock { () -> Bool in
        defer { holdsFirstWrite = false }
        return holdsFirstWrite
      }
      if holds {
        entered.signal()
        gate.wait()
      }
      lock.withLock { log.append("\(key):\(item)") }
    }
  }

  private func makeQueue(_ writer: Writer) -> AppWriteQueue<Int, String> {
    AppWriteQueue(label: "test") { key, item in writer.write(key, item) }
  }

  @Test func writesWhatIsSubmitted() {
    let writer = Writer()
    writer.holdsFirstWrite = false
    let queue = makeQueue(writer)
    queue.submit("a", for: 1)
    queue.waitUntilWritten()
    #expect(writer.written == ["1:a"])
    #expect(queue.takeStatistics().written == 1)
  }

  @Test func onlyTheNewestItemWaitingIsWritten() {
    let writer = Writer()
    let queue = makeQueue(writer)
    queue.submit("a", for: 1)
    writer.entered.wait()
    queue.submit("b", for: 1)
    queue.submit("c", for: 1)
    writer.gate.signal()
    queue.waitUntilWritten()
    #expect(writer.written == ["1:a", "1:c"])
    let statistics = queue.takeStatistics()
    #expect(statistics.written == 2)
    #expect(statistics.skipped == 1)
  }

  @Test func eachKeyKeepsItsOwnNewestItem() {
    let writer = Writer()
    let queue = makeQueue(writer)
    queue.submit("a", for: 1)
    writer.entered.wait()
    queue.submit("b", for: 1)
    queue.submit("x", for: 2)
    writer.gate.signal()
    queue.waitUntilWritten()
    #expect(writer.written.first == "1:a")
    #expect(Set(writer.written.dropFirst()) == ["1:b", "2:x"])
  }

  @Test func aDiscardedItemIsNeverWritten() {
    let writer = Writer()
    let queue = makeQueue(writer)
    queue.submit("a", for: 1)
    writer.entered.wait()
    queue.submit("b", for: 1)
    queue.discard(1)
    writer.gate.signal()
    queue.waitUntilWritten()
    #expect(writer.written == ["1:a"])
    #expect(queue.takeStatistics().skipped == 1)
  }

  @Test func waitingCoversAWriteInProgress() {
    let writer = Writer()
    let queue = makeQueue(writer)
    queue.submit("a", for: 1)
    writer.entered.wait()
    DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(20)) {
      writer.gate.signal()
    }
    queue.waitUntilWritten()
    #expect(writer.written == ["1:a"])
  }

  @Test func statisticsStartOverWhenTaken() {
    let writer = Writer()
    writer.holdsFirstWrite = false
    let queue = makeQueue(writer)
    queue.submit("a", for: 1)
    queue.waitUntilWritten()
    _ = queue.takeStatistics()
    #expect(queue.takeStatistics() == .init())
  }

  @Test func submittingAfterTheQueueRanDryStartsItAgain() {
    let writer = Writer()
    writer.holdsFirstWrite = false
    let queue = makeQueue(writer)
    queue.submit("a", for: 1)
    queue.waitUntilWritten()
    queue.submit("b", for: 1)
    queue.waitUntilWritten()
    #expect(writer.written == ["1:a", "1:b"])
  }
}
