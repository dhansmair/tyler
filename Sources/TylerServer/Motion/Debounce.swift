/// Acts once things have been quiet for a while, like the pointer coming to rest or a burst of
/// display changes ending: each `restart` starts the wait again, and only the last one acts.
@MainActor
final class Debounce {
  private let clock: any Clock<Duration>
  private var task: Task<Void, Never>?

  /// Whether an action is waiting for the quiet to last.
  var isPending: Bool { task != nil }

  init(clock: any Clock<Duration>) {
    self.clock = clock
  }

  /// Drops the action still waiting, if any, and runs `action` once `delay` passes without
  /// another `restart` or a `cancel`.
  func restart(after delay: Duration, then action: @escaping @MainActor () -> Void) {
    task?.cancel()
    let clock = clock  // Swift opens the existential from a local, not from the stored property.
    task = Task { [weak self] in
      do {
        try await clock.sleep(for: delay)
      } catch {
        return  // Cancelled: restarted, or no longer wanted.
      }
      self?.task = nil
      action()
    }
  }

  func cancel() {
    task?.cancel()
    task = nil
  }
}
