import TylerCore

extension Scenario {
  /// `closed` closes and macOS focuses `next` at once, before any time passes.
  func closeThenFocus(_ closed: UInt32, next: UInt32...) async {
    harness.windowSystem.windows.removeAll { $0.id.rawValue == closed }
    harness.windowSystem.send(.destroyed(WindowID(closed)))
    for window in next { harness.windowSystem.send(.focused(WindowID(window))) }
    await runUntilQuiet()
  }

  /// An app quits: macOS focuses `next` and the focus reaches tylerd before the quit does.
  func focusThenClose(_ closed: UInt32, next: UInt32) async {
    harness.windowSystem.send(.focused(WindowID(next)))
    await harness.settle()
    await close(closed)
  }
}
