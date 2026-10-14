import TylerCore

/// Why a backend could not act on a window.
package enum WindowSystemError: Error, Equatable, Sendable, CustomStringConvertible {
  /// The window closed (or its app quit) before the action reached it.
  case windowGone(WindowID)
  /// The app or the system refused; the text says why, and only that: the caller names the action
  /// and the window.
  case refused(String)

  package var description: String {
    switch self {
    case .windowGone: "the window no longer exists"
    case .refused(let reason): reason
    }
  }
}
