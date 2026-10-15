import ApplicationServices
import Foundation
import TylerCore
import TylerRuntime
import TylerServer

/// Asks macOS whether this process (or the terminal app hosting it) may use Accessibility.
@MainActor
package final class MacAccessibilityGate: AccessibilityGate {
  package let changes: AsyncStream<Void>
  private static let log = TylerLog(category: "ax")
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

  package var facts: AccessFacts {
    AccessFacts(isTrusted: isTrusted, probe: Self.probe(), isScreenLocked: Self.isScreenLocked)
  }

  /// Asks for the focused app, which every grant allows: a stale grant was seen to report itself
  /// trusted while tylerd saw no windows.
  private static func probe() -> AccessFacts.Probe {
    let systemWide = AXUIElementCreateSystemWide()
    // The frontmost app answers; one that hangs mustn't hold up the main thread for long.
    _ = AXUIElementSetMessagingTimeout(systemWide, 0.5)
    var value: CFTypeRef?
    let status = AXUIElementCopyAttributeValue(
      systemWide, kAXFocusedApplicationAttribute as CFString, &value)
    switch status {
    case .success, .noValue: return .allowed
    case .apiDisabled:
      log.debug("permission probing failed - AX error \(status.rawValue)")
      return .refused
    default:
      log.debug("permission probing failed - AX error \(status.rawValue)")
      return .noAnswer
    }
  }

  private static var isScreenLocked: Bool {
    guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
    return session["CGSSessionScreenIsLocked"] as? Bool ?? false
  }

  package func prompt() {
    // The literal is the value of `kAXTrustedCheckOptionPrompt`; the constant itself is a
    // mutable global, which Swift 6 strict concurrency rejects.
    let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
  }
}
