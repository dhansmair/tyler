import Foundation
import Testing

@testable import MWMCore

@Suite("Wire protocol")
struct ProtocolTests {
  @Test func requestRoundTrips() throws {
    let data = try Wire.encode(Request.ping)
    let line = data.dropLast()
    #expect(try Wire.decode(Request.self, from: Data(line)) == .ping)
  }

  @Test(arguments: [Response.pong, Response.error("boom")])
  func responseRoundTrips(response: Response) throws {
    let data = try Wire.encode(response)
    #expect(try Wire.decode(Response.self, from: Data(data.dropLast())) == response)
  }

  @Test func encodedMessagesAreSingleNewlineTerminatedLines() throws {
    let data = try Wire.encode(Response.error("multi\nline"))
    let text = String(decoding: data, as: UTF8.self)
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
