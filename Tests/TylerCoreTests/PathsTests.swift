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

  @Test(arguments: [[:], ["TYLER_CONFIG": ""]])
  func configDefaultsToDotConfig(environment: [String: String]) {
    #expect(
      Paths.configPath(environment: environment, home: "/Users/x")
        == "/Users/x/.config/tyler/tyler.toml")
  }

  @Test func configEnvironmentOverrideWins() {
    let env = ["TYLER_CONFIG": "/tmp/other.toml"]
    #expect(Paths.configPath(environment: env, home: "/Users/x") == "/tmp/other.toml")
  }
}
