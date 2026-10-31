import Testing
import TylerClient

@Suite("LogViewing")
struct LogViewingTests {
  @Test func aTerminalFollowsTheLogAcrossRestarts() {
    #expect(
      LogViewing.tailArguments(path: "/logs/tyler.log", isTerminal: true)
        == ["tail", "-n", "50", "-F", "/logs/tyler.log"])
  }

  @Test func withoutATerminalItPrintsTheEndAndExits() {
    #expect(
      LogViewing.tailArguments(path: "/logs/tyler.log", isTerminal: false)
        == ["tail", "-n", "50", "/logs/tyler.log"])
  }
}
