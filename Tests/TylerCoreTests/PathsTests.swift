import Testing

@testable import TylerCore

@Suite("Paths")
struct PathsTests {
  @Test func defaultsToHomeDirectory() {
    #expect(Paths.socketPath(environment: [:], home: "/Users/x") == "/Users/x/.tyler/tyler.sock")
  }

  @Test func environmentOverrideWins() {
    let env = ["TYLER_SOCKET": "/tmp/custom.sock"]
    #expect(Paths.socketPath(environment: env, home: "/Users/x") == "/tmp/custom.sock")
  }

  @Test func emptyOverrideIsIgnored() {
    let env = ["TYLER_SOCKET": ""]
    #expect(Paths.socketPath(environment: env, home: "/Users/x") == "/Users/x/.tyler/tyler.sock")
  }
}
