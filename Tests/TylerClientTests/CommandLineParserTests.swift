import CoreGraphics
import Foundation
import Testing
import TylerCore
import TylerProtocol
import TylerRuntime

@testable import TylerClient

@Suite("CommandLineParser")
struct CommandLineParserTests {
  @Test(arguments: [
    (["ping"], Request.ping), (["window", "list"], .list), (["config", "reload"], .reload),
    (["workspace", "retile"], .retile), (["layout", "next"], .layout(.next)),
    (["window", "close"], .close),
  ])
  func parsesCommandsWithoutArguments(command: [String], request: Request) throws {
    #expect(try CommandLineParser.parse(command) == Invocation(request: request, format: .text))
  }

  @Test func parsesListAsJSON() throws {
    #expect(
      try CommandLineParser.parse(["window", "list", "--json"])
        == Invocation(request: .list, format: .json))
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

  @Test(arguments: [
    ["ping"], ["config", "reload"], ["workspace", "retile"], ["layout", "next"],
    ["window", "close"],
  ])
  func commandsWithoutArgumentsRejectExtraOnes(command: [String]) {
    #expect(throws: CommandLineError.usage("\(command.joined(separator: " ")) takes no arguments"))
    {
      try CommandLineParser.parse(command + ["now"])
    }
  }

  @Test(arguments: [
    ["window", "list", "--yaml"], ["window", "list", "--json", "extra"], ["window", "list", "x"],
  ])
  func listRejectsUnknownArguments(arguments: [String]) {
    #expect(throws: CommandLineError.usage("window list only accepts --json")) {
      try CommandLineParser.parse(arguments)
    }
  }

  /// A noun alone, or with a verb it doesn't have, names the verbs it has.
  @Test(arguments: [
    (
      ["window"],
      "missing window command (use list, focus, swap, promote, demote, float, close, size, "
        + "move-to-workspace, move-to-display)"
    ),
    (["workspace", "3"], "unknown workspace command '3' (use focus, move-to-display, retile)"),
    (["layout", "tall"], "unknown layout command 'tall' (use set, next, ratio)"),
    (["display", "focus2"], "unknown display command 'focus2' (use focus)"),
  ])
  func nounWithoutAKnownVerbNamesItsVerbs(arguments: [String], message: String) {
    #expect(throws: CommandLineError.usage(message)) {
      try CommandLineParser.parse(arguments)
    }
  }

  /// The commands before the grouping by noun are gone, not kept as aliases.
  @Test(arguments: [
    "list", "focus", "swap", "float", "size", "ratio", "retile", "move-to-workspace",
    "move-to-display", "move-workspace-to-display", "reload",
  ])
  func oldCommandNamesAreUnknown(name: String) {
    #expect(throws: CommandLineError.usage("unknown command '\(name)'")) {
      try CommandLineParser.parse([name, "next"])
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
        usage: tyler <command> [arguments]
               tyler <window|workspace|layout|display|config|debug> <command> [arguments]
               tyler --version

        commands:
          start                          start tylerd in the background
          stop                           stop tylerd (windows go back where they were)
          restart                        stop tylerd and start it again, for example after a rebuild
          status                         show whether tylerd is running, and which build
          logs [--level debug|info|warning|error]
                                         show tylerd's log and follow it
          ping                           check that tylerd is running
          tiling on|off|toggle           start or stop tiling (off unparks hidden windows)

          window list [--json]           show the windows tylerd is tracking
          window focus next|prev|master  move focus within the tiling list
          window swap next|prev|master   swap the focused window with another slot
          window promote                 move the focused window into the master section
          window demote                  move the focused window out of the master section
          window float on|off|toggle     float the focused window, or tile it again
          window close                   close the focused window
          window size half|full|quarter|next
                                         size the focused window in the strip layout
          window move-to-workspace prev|next|<n> [--follow]
                                         send the focused window to another workspace
          window move-to-display prev|next|<n> [--follow]
                                         send the focused window to another display

          workspace focus prev|next|<n>  switch to another workspace (prev and next wrap)
          workspace move-to-display prev|next|<n>
                                         move the current workspace to another display
          workspace retile               put every tiled window back into its slot

          layout set tall|grid|full|strip
                                         choose the current workspace's layout
          layout next                    switch to the next layout of layouts.cycle
          layout ratio +0.05|-0.05       widen or narrow the master column

          display focus prev|next|<n>    focus another display (prev and next wrap)

          config get [<setting>]         show a setting, or every setting
          config set <setting> <value>   change a setting until tylerd stops or reloads
          config reload                  read the config file again (drops what set changed)
          config edit                    open the config file in your editor

          debug at [<x> <y>] [--json]    what tylerd sees and does at a point
          debug windows [--json]         where tylerd's picture of the windows differs from macOS's
        """)
  }

  @Test(arguments: [
    (["config", "get"], Request.configGet(nil)),
    (["config", "get", "gaps.inner"], .configGet("gaps.inner")),
    (["config", "set", "gaps.inner", "8"], .configSet(name: "gaps.inner", value: "8")),
    (
      ["config", "set", "layouts.cycle", "[\"tall\",", "\"full\"]"],
      .configSet(name: "layouts.cycle", value: "[\"tall\", \"full\"]")
    ),
  ])
  func parsesConfigCommands(arguments: [String], request: Request) throws {
    #expect(try CommandLineParser.parse(arguments) == Invocation(request: request))
  }

  @Test func configEditIsDoneByTheClient() throws {
    #expect(try CommandLineParser.parse(["config", "edit"]) == Invocation(action: .editConfig))
  }

  @Test(arguments: [
    (["debug", "at"], Invocation(request: .debugAt(nil))),
    (["debug", "at", "300", "-40.5"], Invocation(request: .debugAt(CGPoint(x: 300, y: -40.5)))),
    (["debug", "at", "--json"], Invocation(request: .debugAt(nil), format: .json)),
    (
      ["debug", "at", "1", "2", "--json"],
      Invocation(request: .debugAt(CGPoint(x: 1, y: 2)), format: .json)
    ),
  ])
  func parsesDebugAt(arguments: [String], invocation: Invocation) throws {
    #expect(try CommandLineParser.parse(arguments) == invocation)
  }

  @Test(arguments: [
    (["debug", "windows"], Invocation(request: .debugWindows)),
    (["debug", "windows", "--json"], Invocation(request: .debugWindows, format: .json)),
  ])
  func parsesDebugWindows(arguments: [String], invocation: Invocation) throws {
    #expect(try CommandLineParser.parse(arguments) == invocation)
  }

  @Test(arguments: [
    ["debug", "at", "300"], ["debug", "at", "x", "y"], ["debug", "at", "1", "2", "3"],
  ])
  func debugAtWantsTwoNumbersOrNone(arguments: [String]) {
    #expect(
      throws: CommandLineError.usage(
        "debug at takes a point in screen coordinates, such as 300 400, or nothing for the pointer")
    ) { try CommandLineParser.parse(arguments) }
  }

  @Test(arguments: [
    (
      ["config", "get", "gaps.inner", "gaps.outer"],
      "config get takes at most one argument: a setting's name, such as gaps.inner"
    ),
    (["config", "set"], "config set takes a setting's name and a value, such as gaps.inner 8"),
    (
      ["config", "set", "gaps.inner"],
      "config set takes a setting's name and a value, such as gaps.inner 8"
    ),
    (["config", "edit", "now"], "config edit takes no arguments"),
  ])
  func configCommandsCheckTheirArgumentCount(arguments: [String], message: String) {
    #expect(throws: CommandLineError.usage(message)) {
      try CommandLineParser.parse(arguments)
    }
  }

  @Test func versionIsAnOptionNotACommand() throws {
    #expect(try CommandLineParser.parse(["--version"]) == Invocation(action: .printVersion))
    #expect(throws: CommandLineError.usage("unknown command '--version'")) {
      try CommandLineParser.parse(["--version", "now"])
    }
  }

  @Test func logsTakesNoArguments() throws {
    #expect(try CommandLineParser.parse(["logs"]) == Invocation(action: .showLog(level: nil)))
  }

  @Test(arguments: LogLevel.allCases)
  func logsSetsALevel(level: LogLevel) throws {
    #expect(
      try CommandLineParser.parse(["logs", "--level", level.rawValue])
        == Invocation(action: .showLog(level: level)))
  }

  @Test(arguments: [
    (["logs", "--level"], "logs --level takes exactly one argument: debug|info|warning|error"),
    (
      ["logs", "--level", "loud"],
      "unknown logs --level argument 'loud' (use debug|info|warning|error)"
    ),
    (
      ["logs", "--level", "info", "extra"],
      "logs --level takes exactly one argument: debug|info|warning|error"
    ),
    (["logs", "extra"], "logs takes only --level, not 'extra'"),
  ])
  func logsRefuses(command: [String], message: String) {
    #expect(throws: CommandLineError.usage(message)) { try CommandLineParser.parse(command) }
  }

  /// Every command has a section in the manual's command reference, and every section there is
  /// a command. A heading names one or several commands (`### start, stop, restart`), each by its
  /// full name (`### window focus`).
  @Test func theManualDescribesEveryCommand() throws {
    let manual = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("docs/manual.md")
    let text = try String(contentsOf: manual, encoding: .utf8)
    let reference = try #require(text.components(separatedBy: "\n## Command reference\n").last)
    let section = reference.components(separatedBy: "\n## ").first ?? ""
    var documented: [String] = []
    for line in section.split(separator: "\n") where line.hasPrefix("### ") {
      documented += line.dropFirst(4).split(separator: ",").map {
        $0.trimmingCharacters(in: .whitespaces)
      }
    }
    #expect(Set(documented) == Set(CommandLineParser.commands.map(\.name)))
    #expect(documented.count == CommandLineParser.commands.count, "no command is described twice")
  }

}
