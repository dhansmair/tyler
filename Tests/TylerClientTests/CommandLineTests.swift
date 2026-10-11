import CoreGraphics
import Foundation
import Testing
import TylerCore

@testable import TylerClient

@Suite("CommandLineParser")
struct CommandLineTests {
  @Test(arguments: [("ping", Request.ping), ("list", .list), ("reload", .reload)])
  func parsesCommandsWithoutArguments(command: String, request: Request) throws {
    #expect(try CommandLineParser.parse([command]) == Invocation(request: request, format: .text))
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

  @Test(arguments: ["ping", "reload", "retile"])
  func commandsWithoutArgumentsRejectExtraOnes(command: String) {
    #expect(throws: CommandLineError.usage("\(command) takes no arguments")) {
      try CommandLineParser.parse([command, "now"])
    }
  }

  @Test(arguments: [["list", "--yaml"], ["list", "--json", "extra"], ["list", "x"]])
  func listRejectsUnknownArguments(arguments: [String]) {
    #expect(throws: CommandLineError.usage("list only accepts --json")) {
      try CommandLineParser.parse(arguments)
    }
  }

  @Test(arguments: DaemonCommand.allCases)
  func parsesDaemonCommands(command: DaemonCommand) throws {
    #expect(
      try CommandLineParser.parse([command.rawValue]) == Invocation(action: .daemon(command)))
  }

  @Test(arguments: DaemonCommand.allCases)
  func daemonCommandsRejectArguments(command: DaemonCommand) {
    #expect(throws: CommandLineError.usage("\(command.rawValue) takes no arguments")) {
      try CommandLineParser.parse([command.rawValue, "now"])
    }
  }

  /// The full usage text, so a change to how it is put together can't change what users see.
  @Test func usageReadsExactlyLikeThis() {
    #expect(
      CommandLineParser.usage == """
        usage: tyler <command>

        commands:
          start                          start tylerd in the background
          stop                           stop tylerd (windows go back where they were)
          restart                        stop tylerd and start it again, for example after a rebuild
          status                         show whether tylerd is running, and which build
          ping                           check that tylerd is running
          list [--json]                  show the windows tylerd is tracking
          reload                         read the config file again and apply it
          focus next|prev|master         move focus within the tiling list
          swap next|prev|master          swap the focused window with another slot
          layout tall|full|strip|next    choose the layout
          ratio +0.05|-0.05              widen or narrow the master column
          float toggle                   float the focused window, or tile it again
          tiling on|off|toggle           start or stop tiling (off unparks hidden windows)
          retile                         put every tiled window back into its slot
          workspace prev|next|<n>        switch to another workspace (prev and next wrap)
          move-to-workspace prev|next|<n> [--follow]
                                         send the focused window to another workspace
        """)
  }

  /// Every command has a section in the manual's command reference, and every section there is
  /// a command. A heading may name several commands (`### start, stop, restart`) or carry the
  /// only argument (`### float toggle`).
  @Test func theManualDescribesEveryCommand() throws {
    let manual = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("docs/manual.md")
    let text = try String(contentsOf: manual, encoding: .utf8)
    let reference = try #require(text.components(separatedBy: "\n## Command reference\n").last)
    let section = reference.components(separatedBy: "\n## ").first ?? ""
    var documented: [String] = []
    for line in section.split(separator: "\n") where line.hasPrefix("### ") {
      for name in line.dropFirst(4).split(separator: ",") {
        documented += name.split(separator: " ").prefix(1).map(String.init)
      }
    }
    #expect(Set(documented) == Set(CommandLineParser.commands.map(\.name)))
    #expect(documented.count == CommandLineParser.commands.count, "no command is described twice")
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
    (["workspace", "prev"], Request.workspace(.prev)),
    (["workspace", "next"], Request.workspace(.next)),
    (["workspace", "3"], Request.workspace(.number(3))),
    (["move-to-workspace", "next"], Request.moveToWorkspace(.next, follow: false)),
    (["move-to-workspace", "2", "--follow"], Request.moveToWorkspace(.number(2), follow: true)),
    (["move-to-workspace", "--follow", "prev"], Request.moveToWorkspace(.prev, follow: true)),
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
    (["layout"], "layout takes exactly one argument: tall|full|strip|next"),
    (["layout", "wide"], "unknown layout 'wide' (use tall|full|strip|next)"),
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
    (["workspace"], "workspace takes exactly one argument: prev|next|<n>"),
    (["workspace", "prev", "next"], "workspace takes exactly one argument: prev|next|<n>"),
    (
      ["workspace", "0"], "unknown workspace argument '0' (use prev|next|<n>, where n starts at 1)"
    ),
    (
      ["workspace", "left"],
      "unknown workspace argument 'left' (use prev|next|<n>, where n starts at 1)"
    ),
    (
      ["workspace", "down"],
      "unknown workspace argument 'down' (use prev|next|<n>, where n starts at 1)"
    ),
    (
      ["move-to-workspace"],
      "move-to-workspace takes one target (prev|next|<n>) and optionally --follow"
    ),
    (
      ["move-to-workspace", "--follow"],
      "move-to-workspace takes one target (prev|next|<n>) and optionally --follow"
    ),
    (
      ["move-to-workspace", "1", "2"],
      "move-to-workspace takes one target (prev|next|<n>) and optionally --follow"
    ),
    (
      ["move-to-workspace", "1", "--follow", "--follow"],
      "move-to-workspace takes one target (prev|next|<n>) and optionally --follow"
    ),
    (
      ["move-to-workspace", "-1"],
      "unknown move-to-workspace argument '-1' (use prev|next|<n>, where n starts at 1)"
    ),
  ])
  func rejectsBadArgumentsAndNamesTheValidChoices(arguments: [String], message: String) {
    #expect(throws: CommandLineError.usage(message)) {
      try CommandLineParser.parse(arguments)
    }
  }

}
