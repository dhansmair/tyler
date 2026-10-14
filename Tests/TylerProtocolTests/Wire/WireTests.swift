import Foundation
import Testing
import TylerCore

@testable import TylerProtocol

@Suite("Wire protocol")
struct WireTests {
  @Test func requestRoundTrips() throws {
    let data = try Wire.encode(Request.ping)
    let line = data.dropLast()
    #expect(try Wire.decode(Request.self, from: Data(line)) == .ping)
  }

  @Test(arguments: [
    Request.reload, .status, .list, .retile, .workspace(.prev), .workspace(.next),
    .workspace(.number(3)),
    .moveToWorkspace(.number(2), follow: true), .moveToWorkspace(.next, follow: false),
    .display(.prev), .display(.next), .display(.number(2)),
    .moveToDisplay(.number(2), follow: true), .moveToDisplay(.next, follow: false),
    .moveWorkspaceToDisplay(.prev), .moveWorkspaceToDisplay(.number(2)),
    .debugAt(nil), .debugAt(CGPoint(x: 300, y: -40.5)), .debugWindows,
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
    .pointer(PointerDiagnosis(point: CGPoint(x: 1, y: 2), check: PointerCheck())),
    .drift(
      WindowDrift.compare(believed: [], fresh: FreshWindows(tracked: [], unattachedApps: ["A"]))),
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

  @Test func aStatusFromBeforeHandOverDecodesAsNotKeepingWindows() throws {
    let old = Data(
      #"{"configPath":"/c","executablePath":"/t","pid":7,"startedAt":0,"tiling":"on"}"#.utf8)
    let status = try JSONDecoder().decode(ServerStatus.self, from: old)
    #expect(status.keepsWindowsOnRestart == nil)
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
