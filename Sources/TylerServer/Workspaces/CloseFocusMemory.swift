import TylerCore

/// How long the windows `WindowEventInterpreter` remembers for a close of the focused window
/// count: the window a focus nobody asked for left, and the window that closed with the focus.
@MainActor
final class CloseFocusMemory {
  private let previousFocus: Debounce
  private let closedFocus: Debounce

  init(clock: any Clock<Duration>) {
    previousFocus = Debounce(clock: clock)
    closedFocus = Debounce(clock: clock)
  }

  func focusLeft(then forget: @escaping @MainActor () -> Void) {
    previousFocus.restart(after: WorkspaceController.focusHandoverMemory, then: forget)
  }

  func focusedWindowClosed(then forget: @escaping @MainActor () -> Void) {
    closedFocus.restart(after: WorkspaceController.closedFocusMemory, then: forget)
  }

  func cancel() {
    previousFocus.cancel()
    closedFocus.cancel()
  }
}
