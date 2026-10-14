import CoreGraphics
import Foundation
import Testing
import TylerCore

@testable import TylerProtocol

@Suite("Protocol: list")
struct WireListTests {
  @Test func listRequestRoundTrips() throws {
    let data = try Wire.encode(Request.list)
    #expect(try Wire.decode(Request.self, from: Data(data.dropLast())) == .list)
  }

  @Test func emptyWindowListRoundTrips() throws {
    let data = try Wire.encode(Response.windows([]))
    #expect(try Wire.decode(Response.self, from: Data(data.dropLast())) == .windows([]))
  }

  @Test func windowTitlesWithNewlinesStayOnOneLine() throws {
    let window = WindowInfo(
      id: WindowID(1),
      processID: 1,
      appName: "App",
      title: "line one\nline two",
      frame: .zero
    )
    let data = try Wire.encode(Response.windows([window]))
    let text = try #require(String(data: data, encoding: .utf8))
    #expect(!text.dropLast().contains("\n"))
  }
}
