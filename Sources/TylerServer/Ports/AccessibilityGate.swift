import TylerCore

/// Whether this process may use the Accessibility API.
@MainActor
package protocol AccessibilityGate: AnyObject {
  var isTrusted: Bool { get }
  /// `isTrusted`, one Accessibility read that needs the permission, and the screen lock: what
  /// decides whether tylerd may start (`WindowAccess.beforeStart`).
  var facts: AccessFacts { get }
  /// An element each time macOS says an Accessibility grant may have changed. Only a hint:
  /// `isTrusted` decides.
  var changes: AsyncStream<Void> { get }
  /// Asks macOS to show its permission prompt. Safe to call repeatedly.
  func prompt()
}
