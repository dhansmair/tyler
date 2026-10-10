/// Paces steps that arrive faster than they can be carried out, like a pan's offsets or a drag's
/// frames: after a step, the next one waits out an interval, and updates arriving meanwhile
/// replace each other. The owner keeps the newest update; the throttle only says whether a step
/// may run now, and runs the waiting one when the interval is up.
struct Throttle: Equatable {
  private var task: Task<Void, Never>?

  /// Whether a step ran less than an interval ago, so the next one must wait.
  var isHolding: Bool { task != nil }

  /// Holds further steps back for `interval` on `clock`, then calls `step`. Without an interval,
  /// nothing is held back.
  mutating func hold(
    for interval: Duration, on clock: any Clock<Duration>,
    then step: @escaping @MainActor @Sendable () -> Void
  ) {
    task?.cancel()
    guard interval > .zero else {
      task = nil
      return
    }
    task = Task { @MainActor in
      do {
        try await clock.sleep(for: interval)
      } catch {
        return  // Cancelled: whatever was being paced has ended.
      }
      step()
    }
  }

  /// Lets the next step run at once, dropping any step still waiting.
  mutating func release() {
    task?.cancel()
    task = nil
  }
}
