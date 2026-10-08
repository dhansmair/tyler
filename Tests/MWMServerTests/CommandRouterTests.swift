import MWMCore
import Testing

@testable import MWMServer

@Suite("CommandRouter")
struct CommandRouterTests {
  @Test func pingAnswersPong() {
    #expect(CommandRouter().handle(.ping) == .pong)
  }
}
