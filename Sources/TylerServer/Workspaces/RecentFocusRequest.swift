import TylerCore

/// The window tylerd last asked to focus, for as long as an app's answer can still arrive.
@MainActor
final class RecentFocusRequest {
  private let expiry: Debounce
  private let memory: Duration
  private(set) var request: FocusRequest?

  init(remembering memory: Duration, clock: any Clock<Duration>) {
    self.memory = memory
    expiry = Debounce(clock: clock)
  }

  func note(_ windowID: WindowID) {
    request = FocusRequest(window: windowID, isSecondTry: false)
    expiry.restart(after: memory) { [weak self] in self?.request = nil }
  }

  func markSecondTry() {
    request = request.map { FocusRequest(window: $0.window, isSecondTry: true) }
  }

  func cancel() {
    expiry.cancel()
    request = nil
  }
}
