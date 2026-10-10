import Foundation
import Testing

@testable import TylerCore

@Suite("Wire protocol")
struct ProtocolTests {
  @Test func requestRoundTrips() throws {
    let data = try Wire.encode(Request.ping)
    let line = data.dropLast()
    #expect(try Wire.decode(Request.self, from: Data(line)) == .ping)
  }

  @Test(arguments: [
    Request.reload, .status, .list, .retile, .workspace(.up), .workspace(.down),
    .workspace(.number(3)),
    .moveToWorkspace(.number(2), follow: true), .moveToWorkspace(.down, follow: false),
  ])
  func requestsWithAndWithoutArgumentsRoundTrip(request: Request) throws {
    let data = try Wire.encode(request)
    #expect(try Wire.decode(Request.self, from: Data(data.dropLast())) == request)
  }

  @Test(arguments: [
    Response.pong, .error("boom"),
    .status(
      ServerStatus(
        pid: 42, executablePath: "/bin/tylerd", executableModified: Date(timeIntervalSince1970: 1),
        startedAt: Date(timeIntervalSince1970: 2), configPath: "/c.toml", tiling: .off)),
  ])
  func responseRoundTrips(response: Response) throws {
    let data = try Wire.encode(response)
    #expect(try Wire.decode(Response.self, from: Data(data.dropLast())) == response)
  }

  @Test func encodedMessagesAreSingleNewlineTerminatedLines() throws {
    let data = try Wire.encode(Response.error("multi\nline"))
    let text = try #require(String(data: data, encoding: .utf8))
    #expect(text.hasSuffix("\n"))
    // The embedded newline must be escaped, otherwise framing breaks.
    #expect(text.dropLast().contains("\n") == false)
  }

  @Test func malformedInputThrows() {
    #expect(throws: (any Error).self) {
      try Wire.decode(Request.self, from: Data("not json".utf8))
    }
    #expect(throws: (any Error).self) {
      try Wire.decode(Request.self, from: Data("{\"nope\":{}}".utf8))
    }
  }
}
