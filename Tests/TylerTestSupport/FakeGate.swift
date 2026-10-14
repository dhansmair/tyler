@testable import TylerServer

@MainActor
package final class FakeGate: AccessibilityGate {
  package var isTrusted: Bool
  package private(set) var promptCount = 0

  package init(isTrusted: Bool) {
    self.isTrusted = isTrusted
  }

  package func prompt() { promptCount += 1 }
}
