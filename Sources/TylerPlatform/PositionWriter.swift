import ApplicationServices
import TylerCore
import TylerRuntime

/// Moves windows without waiting for their apps: each app's moves go to an `AppWriteQueue` of its
/// own, so the windows of a frame move side by side, a slow app skips frames instead of holding
/// up the others, and the main thread stays free for input.
@MainActor
final class PositionWriter {
  /// A window and where it goes. An `AXUIElement` is an immutable handle on an element of another
  /// process, and the Accessibility API may be called from any thread.
  struct Move: @unchecked Sendable {
    let element: AXUIElement
    let origin: CGPoint
  }

  nonisolated private static let log = TylerLog(category: "ax")
  private let write: @Sendable (WindowID, Move) -> Void
  private var queues: [pid_t: AppWriteQueue<WindowID, Move>] = [:]

  init(write: @escaping @Sendable (WindowID, Move) -> Void = PositionWriter.moveWindow) {
    self.write = write
  }

  func move(_ windowID: WindowID, _ element: AXUIElement, to origin: CGPoint, in processID: pid_t) {
    queue(for: processID).submit(Move(element: element, origin: origin), for: windowID)
  }

  /// Drops the move still waiting for `windowID` and waits until its app's queue is idle, so a
  /// write on the main thread lands after every move already sent.
  func settle(_ windowID: WindowID, in processID: pid_t) {
    guard let queue = queues[processID] else { return }
    queue.discard(windowID)
    queue.waitUntilWritten()
  }

  /// Forgets an app that quit; a write still under way finishes on its own.
  func forget(_ processID: pid_t) {
    queues[processID] = nil
  }

  func forgetAll() {
    queues = [:]
  }

  /// What the queues wrote since the last call, all apps together.
  func takeStatistics() -> MotionCost.Queued {
    queues.values.reduce(into: MotionCost.Queued()) { total, queue in
      let statistics = queue.takeStatistics()
      total.add(
        written: statistics.written, skipped: statistics.skipped, time: statistics.time,
        slowest: statistics.slowest.map {
          MotionCost.Write(windowID: $0.key, duration: $0.duration)
        })
    }
  }

  private func queue(for processID: pid_t) -> AppWriteQueue<WindowID, Move> {
    if let queue = queues[processID] { return queue }
    let queue = AppWriteQueue<WindowID, Move>(label: "tyler.moves.\(processID)", write: write)
    queues[processID] = queue
    return queue
  }

  nonisolated private static func moveWindow(_ windowID: WindowID, _ move: Move) {
    let status = AXBridge.setPosition(move.origin, of: move.element)
    if status != .success {
      // One missed frame is invisible; the final placement reports real failures.
      log.debug("window sliding failed - #\(windowID) - AX error \(status.rawValue)")
    }
  }
}
