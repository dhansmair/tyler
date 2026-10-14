import Foundation

/// A clock that only moves when the test calls `advance(by:)`, so animations can be stepped
/// (or held mid-way) without sleeping. It is `@unchecked Sendable` because all mutable state is
/// guarded by `lock`.
package final class TestClock: Clock, @unchecked Sendable {
  package struct Instant: InstantProtocol {
    package var offset: Duration

    package func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
    package func duration(to other: Instant) -> Duration { other.offset - offset }
    package static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
  }

  private struct Sleeper {
    let id: UUID
    let deadline: Instant
    let continuation: CheckedContinuation<Void, any Error>
  }

  private let lock = NSLock()
  private var current = Instant(offset: .zero)
  private var sleepers: [Sleeper] = []

  package init() {}

  package var now: Instant { lock.withLock { current } }
  package var minimumResolution: Duration { .zero }

  /// Whether something is waiting for the clock to advance.
  package var hasSleepers: Bool { lock.withLock { !sleepers.isEmpty } }

  package func sleep(until deadline: Instant, tolerance: Duration?) async throws {
    let id = UUID()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        enqueue(Sleeper(id: id, deadline: deadline, continuation: continuation))
      }
    } onCancel: {
      let sleeper = lock.withLock { () -> Sleeper? in
        guard let index = sleepers.firstIndex(where: { $0.id == id }) else { return nil }
        return sleepers.remove(at: index)
      }
      sleeper?.continuation.resume(throwing: CancellationError())
    }
  }

  /// Parks a sleeper until its deadline, or resumes it at once if it is due or cancelled. The
  /// cancellation check happens under the lock so it can't race with the cancellation handler.
  private func enqueue(_ sleeper: Sleeper) {
    enum Outcome { case due, cancelled, waiting }
    let outcome = lock.withLock { () -> Outcome in
      if Task.isCancelled { return .cancelled }
      if sleeper.deadline <= current { return .due }
      sleepers.append(sleeper)
      return .waiting
    }
    switch outcome {
    case .due: sleeper.continuation.resume()
    case .cancelled: sleeper.continuation.resume(throwing: CancellationError())
    case .waiting: break
    }
  }

  package func advance(by duration: Duration) {
    let due = lock.withLock { () -> [Sleeper] in
      current = current.advanced(by: duration)
      let due = sleepers.filter { $0.deadline <= current }
      sleepers.removeAll { $0.deadline <= current }
      return due
    }
    for sleeper in due { sleeper.continuation.resume() }
  }
}
