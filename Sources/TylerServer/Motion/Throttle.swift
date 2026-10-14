/// Paces steps that arrive faster than they can be carried out, like a swipe's offsets or a drag's
/// frames: the next step waits until an interval after the last one began, and updates arriving
/// meanwhile replace each other. The owner keeps the newest update; the throttle only says whether
/// a step may run now, and runs the waiting one when the interval is up.
struct Throttle: Equatable {
  private var task: Task<Void, Never>?

  /// Whether a step ran less than an interval ago, so the next one must wait.
  var isHolding: Bool { task != nil }

  /// Holds further steps back until `interval` after now on `clock`, then calls `step`. Without
  /// an interval, nothing is held back.
  mutating func hold(
    for interval: Duration, on clock: any Clock<Duration>,
    then step: @escaping @MainActor @Sendable () -> Void
  ) {
    task?.cancel()
    guard interval > .zero else {
      task = nil
      return
    }
    task = Self.wait(until: interval, on: clock, then: step)
  }

  /// The deadline is taken now, not when the task first runs: that is after the step that
  /// called `hold`, which may have taken longer than the interval.
  private static func wait(
    until interval: Duration, on clock: some Clock<Duration>,
    then step: @escaping @MainActor @Sendable () -> Void
  ) -> Task<Void, Never> {
    let deadline = clock.now.advanced(by: interval)
    return Task { @MainActor in
      do {
        try await clock.sleep(until: deadline, tolerance: nil)
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
