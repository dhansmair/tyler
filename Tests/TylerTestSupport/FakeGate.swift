import TylerCore
import TylerServer

@MainActor
package final class FakeGate: AccessibilityGate {
  package var isTrusted: Bool
  package var probe = AccessFacts.Probe.allowed
  package var isScreenLocked = false
  package let changes: AsyncStream<Void>
  package private(set) var promptCount = 0
  private let continuation: AsyncStream<Void>.Continuation

  package init(isTrusted: Bool) {
    self.isTrusted = isTrusted
    (changes, continuation) = AsyncStream.makeStream(of: Void.self)
  }

  package var facts: AccessFacts {
    AccessFacts(isTrusted: isTrusted, probe: probe, isScreenLocked: isScreenLocked)
  }

  package func prompt() { promptCount += 1 }

  /// What macOS posts when a grant is switched in System Settings.
  package func announceChange() { continuation.yield() }
}
