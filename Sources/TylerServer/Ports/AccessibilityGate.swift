/// Whether this process may use the Accessibility API.
@MainActor
package protocol AccessibilityGate: AnyObject {
  var isTrusted: Bool { get }
  /// Asks macOS to show its permission prompt. Safe to call repeatedly.
  func prompt()
}
