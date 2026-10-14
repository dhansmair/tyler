import ApplicationServices
import TylerServer

/// Asks macOS whether this process (or the terminal app hosting it) may use Accessibility.
@MainActor
package final class SystemAccessibilityGate: AccessibilityGate {
  package init() {}

  package var isTrusted: Bool { AXIsProcessTrusted() }

  package func prompt() {
    // The literal is the value of `kAXTrustedCheckOptionPrompt`; the constant itself is a
    // mutable global, which Swift 6 strict concurrency rejects.
    let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
  }
}
