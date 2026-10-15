/// Whether this process may use the Accessibility API.
@MainActor
package protocol AccessibilityGate: AnyObject {
  var isTrusted: Bool { get }
  /// An element each time macOS says an Accessibility grant may have changed. Only a hint:
  /// `isTrusted` decides.
  var changes: AsyncStream<Void> { get }
  /// Asks macOS to show its permission prompt. Safe to call repeatedly.
  func prompt()
}
