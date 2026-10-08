import CoreGraphics
import Foundation
import MWMCore
import Testing

@testable import MWMClient

@Suite("CommandLineParser")
struct CommandLineTests {
  @Test func parsesPing() throws {
    #expect(try CommandLineParser.parse(["ping"]) == Invocation(request: .ping))
  }

  @Test func parsesListAsText() throws {
    #expect(try CommandLineParser.parse(["list"]) == Invocation(request: .list, format: .text))
  }

  @Test func parsesListAsJSON() throws {
    #expect(
      try CommandLineParser.parse(["list", "--json"]) == Invocation(request: .list, format: .json)
    )
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

  @Test(arguments: [["list", "--yaml"], ["list", "--json", "extra"], ["list", "x"]])
  func listRejectsUnknownArguments(arguments: [String]) {
    #expect(throws: CommandLineError.usage("list only accepts --json")) {
      try CommandLineParser.parse(arguments)
    }
  }

  @Test func usageMentionsEveryCommand() {
    #expect(CommandLineParser.usage.contains("ping"))
    #expect(CommandLineParser.usage.contains("list"))
  }
}

@Suite("ResponseFormatter")
struct ResponseFormatterTests {
  private func window(
    id: UInt32,
    app: String = "TextEdit",
    title: String = "Untitled",
    kind: WindowKind = .standard,
    isMinimized: Bool = false,
    isFullscreen: Bool = false,
    isFocused: Bool = false,
    displayID: UInt32? = 1
  ) -> WindowInfo {
    WindowInfo(
      id: WindowID(id),
      processID: 1,
      appName: app,
      title: title,
      frame: CGRect(x: 55, y: 38, width: 800, height: 600),
      kind: kind,
      isMinimized: isMinimized,
      isFullscreen: isFullscreen,
      isFocused: isFocused,
      displayID: displayID
    )
  }

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

  @Test func errorsAreFailuresInJSONModeToo() {
    #expect(!ResponseFormatter.format(.error("nope"), as: .json).success)
  }

  @Test func emptyListSaysSo() {
    let result = ResponseFormatter.format(.windows([]))
    #expect(result.text == "no windows")
    #expect(result.success)
  }

  @Test func tableHasAHeaderAndOneRowPerWindow() {
    let result = ResponseFormatter.format(
      .windows([window(id: 7, isFocused: true), window(id: 12, app: "Terminal", title: "zsh")])
    )
    let lines = result.text.split(separator: "\n").map(String.init)
    #expect(lines.count == 3)
    #expect(lines[0].hasPrefix("ID"))
    #expect(lines[1].contains("TextEdit"))
    #expect(lines[1].contains("55,38 800x600"))
    #expect(lines[1].hasSuffix("focused"))
    #expect(lines[2].contains("Terminal"))
    #expect(lines[2].hasSuffix("-"))
  }

  @Test func tableColumnsLineUp() {
    let result = ResponseFormatter.format(
      .windows([window(id: 1), window(id: 123_456, app: "A much longer app name")])
    )
    let lines = result.text.split(separator: "\n").map(String.init)
    // The widest ID is "123456" (6 characters), then a two-space gap, so APP starts at column 8.
    let appColumn = 8
    let expected = ["APP", "TextEdit", "A much longer app name"]
    for (line, text) in zip(lines, expected) {
      #expect(line.dropFirst(appColumn).hasPrefix(text), "\(text) should start at column 8")
    }
    #expect(lines.allSatisfy { !$0.hasSuffix(" ") }, "no trailing whitespace")
  }

  @Test func flagsDescribeTheWindow() {
    #expect(ResponseFormatter.flags(of: window(id: 1)) == "-")
    #expect(ResponseFormatter.flags(of: window(id: 1, isFocused: true)) == "focused")
    #expect(ResponseFormatter.flags(of: window(id: 1, isMinimized: true)) == "min")
    #expect(ResponseFormatter.flags(of: window(id: 1, isFullscreen: true)) == "full")
    #expect(ResponseFormatter.flags(of: window(id: 1, kind: .dialog)) == "dialog")
    #expect(ResponseFormatter.flags(of: window(id: 1, kind: .floating)) == "float")
    #expect(ResponseFormatter.flags(of: window(id: 1, kind: .other)) == "other")
    #expect(
      ResponseFormatter.flags(of: window(id: 1, isMinimized: true, isFocused: true))
        == "focused,min"
    )
  }

  @Test func titlesWithNewlinesStayOnOneRow() {
    let result = ResponseFormatter.format(.windows([window(id: 1, title: "a\nb")]))
    #expect(result.text.split(separator: "\n").count == 2)
  }

  @Test func missingTitleAndDisplayShowADash() {
    let text = ResponseFormatter.format(.windows([window(id: 1, title: "", displayID: nil)])).text
    let row = text.split(separator: "\n").map(String.init)[1]
    #expect(row.split(separator: " ").filter { $0 == "-" }.count >= 2)
  }

  @Test func jsonIsAnArrayOfWindows() throws {
    let result = ResponseFormatter.format(.windows([window(id: 5)]), as: .json)
    #expect(result.success)
    let data = try #require(result.text.data(using: .utf8))
    let decoded = try JSONDecoder().decode([WindowInfo].self, from: data)
    #expect(decoded == [window(id: 5)])
  }

  @Test func jsonOfNoWindowsIsAnEmptyArray() throws {
    let result = ResponseFormatter.format(.windows([]), as: .json)
    let data = try #require(result.text.data(using: .utf8))
    #expect(try JSONDecoder().decode([WindowInfo].self, from: data).isEmpty)
  }
}
