import MWMCore
import Testing

@testable import MWMClient

@Suite("CommandLineParser")
struct CommandLineTests {
  @Test func parsesPing() throws {
    #expect(try CommandLineParser.parse(["ping"]) == .ping)
  }

  @Test func missingCommandIsAUsageError() {
    #expect(throws: CommandLineError.usage("missing command")) {
      try CommandLineParser.parse([])
    }
  }

  @Test func unknownCommandIsAUsageError() {
    #expect(throws: CommandLineError.usage("unknown command 'frobnicate'")) {
      try CommandLineParser.parse(["frobnicate"])
    }
  }

  @Test func pingRejectsExtraArguments() {
    #expect(throws: CommandLineError.usage("ping takes no arguments")) {
      try CommandLineParser.parse(["ping", "now"])
    }
  }
}

@Suite("ResponseFormatter")
struct ResponseFormatterTests {
  @Test func pongIsASuccess() {
    let result = ResponseFormatter.format(.pong)
    #expect(result.text == "pong")
    #expect(result.success)
  }

  @Test func errorsAreFailures() {
    let result = ResponseFormatter.format(.error("nope"))
    #expect(result.text == "nope")
    #expect(!result.success)
  }
}
