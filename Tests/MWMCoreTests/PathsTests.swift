import Testing

@testable import MWMCore

@Suite("Paths")
struct PathsTests {
  @Test func defaultsToHomeDirectory() {
    #expect(Paths.socketPath(environment: [:], home: "/Users/x") == "/Users/x/.mwm/mwm.sock")
  }

  @Test func environmentOverrideWins() {
    let env = ["MWM_SOCKET": "/tmp/custom.sock"]
    #expect(Paths.socketPath(environment: env, home: "/Users/x") == "/tmp/custom.sock")
  }

  @Test func emptyOverrideIsIgnored() {
    let env = ["MWM_SOCKET": ""]
    #expect(Paths.socketPath(environment: env, home: "/Users/x") == "/Users/x/.mwm/mwm.sock")
  }
}
