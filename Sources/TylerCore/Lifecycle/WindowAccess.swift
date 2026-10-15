/// Whether tylerd can reach the windows through Accessibility, and if not, why. A grant can look
/// fine and still not work: after an update or a new login, macOS may keep a stale entry that is
/// listed and switched on, while tylerd sees no windows.
package enum WindowAccess: String, Codable, Equatable, Sendable {
  case ok
  case notTrusted
  /// The permission is reported granted, but macOS refuses Accessibility calls.
  case refused
  /// macOS reports no windows while the screen is locked (`devdocs/macos-behaviour.md`).
  case screenLocked
  /// Apps are still being observed, so seeing none of their windows doesn't mean much yet.
  case checking
  /// Tracking, but none of the windows the window server shows on screen.
  case blind

  /// Whether tylerd may start tracking windows: `ok`, or why not.
  package static func beforeStart(_ facts: AccessFacts) -> WindowAccess {
    if !facts.isTrusted { return .notTrusted }
    if facts.isScreenLocked { return .screenLocked }
    if facts.probe == .refused { return .refused }
    return .ok
  }

  /// Whether tracking sees the windows: `onScreen` are the window server's windows of the apps
  /// tylerd observes, `known` the windows it tracks. One window in both is enough; with nothing on
  /// screen there is nothing to compare.
  package static func whileRunning(
    onScreen: Set<WindowID>, known: Set<WindowID>, isAttaching: Bool
  ) -> WindowAccess {
    if onScreen.isEmpty || !onScreen.isDisjoint(with: known) { return .ok }
    return isAttaching ? .checking : .blind
  }

  /// Whether tylerd works as it should, or will once the screen is unlocked or the apps answer.
  package var isHealthy: Bool {
    switch self {
    case .ok, .screenLocked, .checking: true
    case .notTrusted, .refused, .blind: false
    }
  }
}
