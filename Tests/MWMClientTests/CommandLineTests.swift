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

@Suite("CommandLineParser: tiling commands")
struct TilingCommandLineTests {
  @Test(arguments: [
    (["focus", "next"], Request.focus(.next)),
    (["focus", "prev"], Request.focus(.prev)),
    (["focus", "master"], Request.focus(.main)),
    (["swap", "next"], Request.swap(.next)),
    (["swap", "prev"], Request.swap(.prev)),
    (["swap", "master"], Request.swap(.main)),
    (["layout", "tall"], Request.layout(.set(.tall))),
    (["layout", "full"], Request.layout(.set(.full))),
    (["layout", "next"], Request.layout(.next)),
    (["ratio", "+0.05"], Request.ratio(0.05)),
    (["ratio", "-0.05"], Request.ratio(-0.05)),
    (["ratio", "+1"], Request.ratio(1)),
    (["float", "toggle"], Request.toggleFloat),
    (["tiling", "on"], Request.tiling(.on)),
    (["tiling", "off"], Request.tiling(.off)),
    (["tiling", "toggle"], Request.tiling(.toggle)),
    (["retile"], Request.retile),
    (["monitor", "up"], Request.monitor(.up)),
    (["monitor", "down"], Request.monitor(.down)),
    (["monitor", "3"], Request.monitor(.number(3))),
    (["move-to-monitor", "down"], Request.moveToMonitor(.down, follow: false)),
    (["move-to-monitor", "2", "--follow"], Request.moveToMonitor(.number(2), follow: true)),
    (["move-to-monitor", "--follow", "up"], Request.moveToMonitor(.up, follow: true)),
  ])
  func parsesEveryTilingCommand(arguments: [String], expected: Request) throws {
    #expect(try CommandLineParser.parse(arguments) == Invocation(request: expected))
  }

  @Test(arguments: [
    (["focus"], "focus takes exactly one argument: next|prev|master"),
    (["focus", "left"], "unknown focus argument 'left' (use next|prev|master)"),
    (["focus", "next", "prev"], "focus takes exactly one argument: next|prev|master"),
    (["swap"], "swap takes exactly one argument: next|prev|master"),
    (["swap", "up"], "unknown swap argument 'up' (use next|prev|master)"),
    (["layout"], "layout takes exactly one argument: tall|full|next"),
    (["layout", "wide"], "unknown layout 'wide' (use tall|full|next)"),
    (["ratio"], "ratio takes exactly one argument, such as +0.05 or -0.05"),
    (["ratio", "0.05"], "ratio must be a signed number such as +0.05 or -0.05"),
    (["ratio", "+abc"], "ratio must be a signed number such as +0.05 or -0.05"),
    (["ratio", "+inf"], "ratio must be a signed number such as +0.05 or -0.05"),
    (["ratio", "+nan"], "ratio must be a signed number such as +0.05 or -0.05"),
    (["ratio", "+0.05", "+0.05"], "ratio takes exactly one argument, such as +0.05 or -0.05"),
    (["float"], "float takes exactly one argument: toggle"),
    (["float", "on"], "float takes exactly one argument: toggle"),
    (["tiling"], "tiling takes exactly one argument: on|off|toggle"),
    (["tiling", "maybe"], "unknown tiling argument 'maybe' (use on|off|toggle)"),
    (["retile", "now"], "retile takes no arguments"),
    (["monitor"], "monitor takes exactly one argument: up|down|<n>"),
    (["monitor", "up", "down"], "monitor takes exactly one argument: up|down|<n>"),
    (["monitor", "0"], "unknown monitor argument '0' (use up|down|<n>, where n starts at 1)"),
    (
      ["monitor", "left"], "unknown monitor argument 'left' (use up|down|<n>, where n starts at 1)"
    ),
    (["move-to-monitor"], "move-to-monitor takes one target (up|down|<n>) and optionally --follow"),
    (
      ["move-to-monitor", "--follow"],
      "move-to-monitor takes one target (up|down|<n>) and optionally --follow"
    ),
    (
      ["move-to-monitor", "1", "2"],
      "move-to-monitor takes one target (up|down|<n>) and optionally --follow"
    ),
    (
      ["move-to-monitor", "1", "--follow", "--follow"],
      "move-to-monitor takes one target (up|down|<n>) and optionally --follow"
    ),
    (
      ["move-to-monitor", "-1"],
      "unknown move-to-monitor argument '-1' (use up|down|<n>, where n starts at 1)"
    ),
  ])
  func rejectsBadArgumentsAndNamesTheValidChoices(arguments: [String], message: String) {
    #expect(throws: CommandLineError.usage(message)) {
      try CommandLineParser.parse(arguments)
    }
  }

  @Test func usageMentionsEveryTilingCommand() {
    for word in [
      "focus", "swap", "layout", "ratio", "float", "tiling", "retile", "monitor", "move-to-monitor",
      "--follow",
    ] {
      #expect(CommandLineParser.usage.contains(word), "usage should mention \(word)")
    }
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
    // The widest ID is "123456" (6 characters), then a two-space gap, the 7-character MONITOR
    // column, the 4-character SLOT column and a two-space gap after each, so APP starts at 23.
    let appColumn = 23
    let expected = ["APP", "TextEdit", "A much longer app name"]
    for (line, text) in zip(lines, expected) {
      #expect(
        line.dropFirst(appColumn).hasPrefix(text), "\(text) should start at column \(appColumn)")
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

  @Test func okPrintsNothingAndSucceeds() {
    let result = ResponseFormatter.format(.ok)
    #expect(result.text.isEmpty)
    #expect(result.success)
  }

  @Test func messagesAreSuccessesThatPrintTheirText() {
    let result = ResponseFormatter.format(.message("tiling on"))
    #expect(result.text == "tiling on")
    #expect(result.success)
  }

  @Test func theTableShowsSlotsAndTheFloatedFlag() {
    var tiled = window(id: 1)
    tiled.slot = 1
    var floating = window(id: 2)
    floating.isFloated = true
    let lines = ResponseFormatter.format(.windows([tiled, floating])).text
      .split(separator: "\n").map(String.init)
    #expect(lines[0].contains("SLOT"))
    #expect(lines[1].split(separator: " ").contains("1"))
    #expect(lines[2].hasSuffix("floated"))
  }

  @Test func theTableShowsTheMonitor() {
    var tiled = window(id: 1)
    tiled.monitor = 2
    tiled.slot = 1
    let lines = ResponseFormatter.format(.windows([tiled, window(id: 2)])).text
      .split(separator: "\n").map(String.init)
    #expect(lines[0].hasPrefix("ID  MONITOR  SLOT"))
    #expect(lines[1].hasPrefix("1   2        1"))
    #expect(lines[2].hasPrefix("2   -        -"))
  }

  @Test func jsonCarriesTheTilingFields() throws {
    var tiled = window(id: 1)
    tiled.slot = 3
    tiled.monitor = 4
    tiled.isFloated = true
    let text = ResponseFormatter.format(.windows([tiled]), as: .json).text
    let decoded = try JSONDecoder().decode([WindowInfo].self, from: Data(text.utf8))
    #expect(decoded.first?.slot == 3)
    #expect(decoded.first?.monitor == 4)
    #expect(decoded.first?.isFloated == true)
  }
}
