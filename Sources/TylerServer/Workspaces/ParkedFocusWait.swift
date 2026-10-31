import TylerCore

/// The wait for a focus on a parked window to last, and the window that held the focus when it
/// began: in a chain of focuses, the later ones only came from each other.
@MainActor
final class ParkedFocusWait {
  private let debounce: Debounce
  private(set) var origin: FocusedWindow?

  var isPending: Bool { debounce.isPending }

  init(clock: any Clock<Duration>) {
    debounce = Debounce(clock: clock)
  }

  /// Starts the wait again, keeping the origin of one already running, and hands `action` the
  /// origin once `delay` passes.
  func restart(
    after delay: Duration, from previous: FocusedWindow?,
    then action: @escaping @MainActor (FocusedWindow?) -> Void
  ) {
    if !isPending { origin = previous }
    debounce.restart(after: delay) { [weak self] in
      let origin = self?.origin
      self?.origin = nil
      action(origin)
    }
  }

  func cancel() {
    debounce.cancel()
    origin = nil
  }
}
