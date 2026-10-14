import ApplicationServices
import Testing
import TylerServer

@testable import TylerPlatform

@Suite("MacWindowSystem")
@MainActor
struct MacWindowSystemTests {
  @Test(arguments: [
    (AXError.cannotComplete, "its app didn't answer"),
    (AXError.attributeUnsupported, "AX error -25205"),
  ])
  func aRefusalGivesOnlyTheReason(status: AXError, reason: String) {
    #expect(MacWindowSystem.refusal(status) == .refused(reason))
  }
}
