import Dispatch
import os

/// Writes to one app on a serial queue of its own. An Accessibility call blocks until the app
/// answers, so writing from the main thread let a slow app hold up every other window of a frame,
/// and the input taps with them. Only the newest item per key is written: an item still waiting
/// when a newer one comes is skipped, so a slow app falls behind by skipping frames, not by
/// queueing them.
final class AppWriteQueue<Key: Hashable & Sendable, Item: Sendable>: Sendable {
  struct Statistics: Equatable, Sendable {
    var written = 0
    var skipped = 0
    var time = Duration.zero
    var slowest: (key: Key, duration: Duration)?

    static func == (lhs: Self, rhs: Self) -> Bool {
      lhs.written == rhs.written && lhs.skipped == rhs.skipped && lhs.time == rhs.time
        && lhs.slowest?.key == rhs.slowest?.key && lhs.slowest?.duration == rhs.slowest?.duration
    }
  }

  private struct State: Sendable {
    var pending: [Key: Item] = [:]
    var isDraining = false
    var statistics = Statistics()
  }

  private let queue: DispatchQueue
  private let state = OSAllocatedUnfairLock(initialState: State())
  private let write: @Sendable (Key, Item) -> Void

  init(label: String, write: @escaping @Sendable (Key, Item) -> Void) {
    queue = DispatchQueue(label: label, qos: .userInteractive)
    self.write = write
  }

  /// Writes `item` soon, replacing an item for `key` that is still waiting.
  func submit(_ item: Item, for key: Key) {
    let startsDraining = state.withLock { state in
      if state.pending.updateValue(item, forKey: key) != nil { state.statistics.skipped += 1 }
      guard !state.isDraining else { return false }
      state.isDraining = true
      return true
    }
    if startsDraining { queue.async { self.drain() } }
  }

  /// Drops the item waiting for `key`, if any: a write on the caller's thread replaces it.
  func discard(_ key: Key) {
    state.withLock { state in
      if state.pending.removeValue(forKey: key) != nil { state.statistics.skipped += 1 }
    }
  }

  /// Returns once every item submitted so far is written. Never call it from a write.
  func waitUntilWritten() {
    queue.sync {}
  }

  /// What was written since the last call.
  func takeStatistics() -> Statistics {
    state.withLock { state in
      defer { state.statistics = Statistics() }
      return state.statistics
    }
  }

  private func drain() {
    let clock = ContinuousClock()
    while true {
      let batch = state.withLock { state in
        let batch = state.pending
        state.pending = [:]
        if batch.isEmpty { state.isDraining = false }
        return batch
      }
      if batch.isEmpty { return }
      for (key, item) in batch {
        let duration = clock.measure { write(key, item) }
        state.withLock { state in
          state.statistics.written += 1
          state.statistics.time += duration
          if duration > state.statistics.slowest?.duration ?? .zero {
            state.statistics.slowest = (key, duration)
          }
        }
      }
    }
  }
}
