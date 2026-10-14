import ApplicationServices
import Testing
import TylerServer

@testable import TylerPlatform

@Suite("AXBackend")
@MainActor
struct AXBackendTests {
  @Test(arguments: [
    (AXError.cannotComplete, "its app didn't answer"),
    (AXError.attributeUnsupported, "AX error -25205"),
  ])
  func aRefusalGivesOnlyTheReason(status: AXError, reason: String) {
    #expect(AXBackend.refusal(status) == .refused(reason))
  }
}
