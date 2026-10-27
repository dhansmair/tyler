import os

/// The lines a manager wrote to its log, at or above its `log.level`. The sink may be called off
/// the main thread (the IPC server logs there), hence the lock.
package final class LogLines: Sendable {
  private let lines = OSAllocatedUnfairLock(initialState: [String]())

  package init() {}

  package var all: [String] { lines.withLock { $0 } }

  func append(_ line: String) { lines.withLock { $0.append(line) } }
}
