import TylerCore

/// A change in the set of windows, reported by a `WindowSystem`.
package enum WindowEvent: Equatable, Sendable {
  case created(WindowInfo)
  case updated(WindowInfo)
  case destroyed(WindowID)
  /// The focused window changed; `nil` when no window has focus.
  case focused(WindowID?)
}
