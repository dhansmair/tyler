import CoreGraphics
import Foundation
import Testing
import TylerCore

@testable import TylerProtocol

@Suite("Protocol: commands")
struct WireCommandsTests {
  static let requests: [Request] = [
    .retile,
    .tiling(.on), .tiling(.off), .tiling(.toggle),
    .focus(.next), .focus(.prev), .focus(.main),
    .swap(.next), .swap(.prev), .swap(.main),
    .layout(.set(.tall)), .layout(.set(.full)), .layout(.next),
    .ratio(0.05), .ratio(-0.05),
    .float(.on), .float(.off), .float(.toggle),
    .close,
  ]

  @Test(arguments: requests)
  func requestRoundTripsOnOneLine(request: Request) throws {
    let data = try Wire.encode(request)
    let text = try #require(String(data: data, encoding: .utf8))
    #expect(!text.dropLast().contains("\n"))
    #expect(try Wire.decode(Request.self, from: Data(data.dropLast())) == request)
  }

  @Test(arguments: [Response.ok, Response.message("tiling on"), Response.error("tiling is off")])
  func responseRoundTrips(response: Response) throws {
    let data = try Wire.encode(response)
    #expect(try Wire.decode(Response.self, from: Data(data.dropLast())) == response)
  }

  @Test func tilingFieldsSurviveTheWire() throws {
    var window = WindowInfo(
      id: WindowID(1), processID: 1, appName: "App", frame: .zero, slot: 2, isFloated: true)
    window.title = "t"
    let data = try Wire.encode(Response.windows([window]))
    let decoded = try Wire.decode(Response.self, from: Data(data.dropLast()))
    #expect(decoded == .windows([window]))
    guard case .windows(let windows) = decoded else { return }
    #expect(windows.first?.slot == 2)
    #expect(windows.first?.isFloated == true)
  }

  @Test func theBareRequestNamesStillDecode() throws {
    // `ping` and `list` must keep their wire format so older clients keep working.
    #expect(try Wire.decode(Request.self, from: Data("{\"ping\":{}}".utf8)) == .ping)
    #expect(try Wire.decode(Request.self, from: Data("{\"list\":{}}".utf8)) == .list)
  }
}
