import TylerCore

/// A change in the set of windows, reported by a `WindowSystem`.
package enum WindowEvent: Equatable, Sendable {
  case created(WindowInfo)
  case updated(WindowInfo)
  /// Windows that changed at one stroke, as hiding or showing their app changes all of them. One
  /// event, so they are tiled once, not through each layout in between.
  case updatedTogether([WindowInfo])
  case destroyed(WindowID)
  /// The focused window changed; `nil` when no window has focus.
  case focused(WindowID?)
}
