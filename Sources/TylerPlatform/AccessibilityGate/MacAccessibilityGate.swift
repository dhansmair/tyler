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
  private let screenLock: any ScreenLock

  package init(screenLock: any ScreenLock) {
    self.screenLock = screenLock
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
    AccessFacts(isTrusted: isTrusted, probe: Self.probe(), isScreenLocked: screenLock.isLocked)
  }

  /// Asks for the focused app, which any working grant allows: a stale grant may report itself
  /// trusted and still have its calls refused (unverified; issue #10).
  private static func probe() -> AccessFacts.Probe {
    let systemWide = AXUIElementCreateSystemWide()
    // The frontmost app answers, so one that hangs would hold up the main thread. On the
    // system-wide element the timeout applies to every element, so it is the window system's.
    _ = AXUIElementSetMessagingTimeout(systemWide, AXBridge.messagingTimeout)
    var value: CFTypeRef?
    let status = AXUIElementCopyAttributeValue(
      systemWide, kAXFocusedApplicationAttribute as CFString, &value)
    if status == .success || status == .noValue { return .allowed }
    log.debug("permission probing failed - AX error \(status.rawValue)")
    return status == .apiDisabled ? .refused : .noAnswer
  }

  package func prompt() {
    // The literal is the value of `kAXTrustedCheckOptionPrompt`; the constant itself is a
    // mutable global, which Swift 6 strict concurrency rejects.
    let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
  }
}
