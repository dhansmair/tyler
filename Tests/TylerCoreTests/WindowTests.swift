import CoreGraphics
import Foundation
import Testing

@testable import TylerCore

@Suite("WindowKind")
struct WindowKindTests {
  struct Case: Sendable {
    let role: String?
    let subrole: String?
    let expected: WindowKind
  }

  @Test(
    arguments: [
      Case(role: "AXWindow", subrole: "AXStandardWindow", expected: .standard),
      Case(role: "AXWindow", subrole: "AXDialog", expected: .dialog),
      Case(role: "AXWindow", subrole: "AXSystemDialog", expected: .dialog),
      Case(role: "AXSheet", subrole: nil, expected: .dialog),
      Case(role: "AXWindow", subrole: "AXFloatingWindow", expected: .floating),
      Case(role: "AXWindow", subrole: "AXSystemFloatingWindow", expected: .floating),
      Case(role: "AXWindow", subrole: "AXUnknown", expected: .other),
      Case(role: "AXWindow", subrole: nil, expected: .other),
      Case(role: nil, subrole: nil, expected: .other),
      Case(role: "AXButton", subrole: "AXStandardWindow", expected: .other),
    ]
  )
  func classifiesRoleAndSubrole(testCase: Case) {
    #expect(
      WindowKind.classify(role: testCase.role, subrole: testCase.subrole) == testCase.expected)
  }
}

@Suite("WindowInfo")
struct WindowInfoTests {
  private func makeWindow(
    kind: WindowKind = .standard,
    isMinimized: Bool = false,
    isFullscreen: Bool = false
  ) -> WindowInfo {
    WindowInfo(
      id: WindowID(42),
      processID: 100,
      appName: "TextEdit",
      frame: CGRect(x: 10, y: 20, width: 300, height: 200),
      kind: kind,
      isMinimized: isMinimized,
      isFullscreen: isFullscreen
    )
  }

  @Test func roundTripsThroughJSON() throws {
    var window = makeWindow()
    window.bundleID = "com.apple.TextEdit"
    window.title = "Untitled — Edited"
    window.displayID = 7
    let data = try Wire.encode(Response.windows([window]))
    let decoded = try Wire.decode(Response.self, from: Data(data.dropLast()))
    #expect(decoded == .windows([window]))
  }

  @Test func windowIDEncodesAsABareNumber() throws {
    let data = try JSONEncoder().encode(WindowID(42))
    #expect(String(data: data, encoding: .utf8) == "42")
  }

  @Test func windowsAreOrderedByID() {
    #expect(
      [WindowID(3), WindowID(1), WindowID(2)].sorted() == [WindowID(1), WindowID(2), WindowID(3)])
  }

  @Test func onlyOnScreenStandardWindowsAreTileable() {
    #expect(makeWindow().isTileable)
    #expect(!makeWindow(kind: .dialog).isTileable)
    #expect(!makeWindow(kind: .floating).isTileable)
    #expect(!makeWindow(kind: .other).isTileable)
    #expect(!makeWindow(isMinimized: true).isTileable)
    #expect(!makeWindow(isFullscreen: true).isTileable)
  }
}

@Suite("Protocol: list")
struct ListProtocolTests {
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

@Suite("Protocol: commands")
struct CommandProtocolTests {
  static let requests: [Request] = [
    .retile,
    .tiling(.on), .tiling(.off), .tiling(.toggle),
    .focus(.next), .focus(.prev), .focus(.main),
    .swap(.next), .swap(.prev), .swap(.main),
    .layout(.set(.tall)), .layout(.set(.full)), .layout(.next),
    .ratio(0.05), .ratio(-0.05),
    .toggleFloat,
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
