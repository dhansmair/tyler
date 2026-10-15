import ApplicationServices
import Foundation
import TylerServer

/// Asks macOS whether this process (or the terminal app hosting it) may use Accessibility.
@MainActor
package final class MacAccessibilityGate: AccessibilityGate {
  package let changes: AsyncStream<Void>
  private let observer: any NSObjectProtocol

  package init() {
    let (changes, continuation) = AsyncStream.makeStream(of: Void.self)
    self.changes = changes
    // Posted when a grant is switched on or off in System Settings, not when an entry is removed
    // (reported on Apple's developer forums; see "Events and taps" in devdocs/macos-behaviour.md).
    observer = DistributedNotificationCenter.default().addObserver(
      forName: NSNotification.Name("com.apple.accessibility.api"), object: nil, queue: .main
    ) { _ in continuation.yield() }
  }

  isolated deinit {
    DistributedNotificationCenter.default().removeObserver(observer)
  }

  package var isTrusted: Bool { AXIsProcessTrusted() }

  package func prompt() {
    // The literal is the value of `kAXTrustedCheckOptionPrompt`; the constant itself is a
    // mutable global, which Swift 6 strict concurrency rejects.
    let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
  }
}
