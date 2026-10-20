import Testing
import TylerCore
import TylerProtocol

@testable import TylerClient

@Suite("CommandLineParser: tiling commands")
struct CommandLineParserTilingTests {
  private static let tilingCommands: [([String], Request)] = [
    (["window", "focus", "next"], Request.focus(.next)),
    (["window", "focus", "prev"], Request.focus(.prev)),
    (["window", "focus", "master"], Request.focus(.main)),
    (["window", "swap", "next"], Request.swap(.next)),
    (["window", "swap", "prev"], Request.swap(.prev)),
    (["window", "swap", "master"], Request.swap(.main)),
    (["window", "promote"], Request.promote),
    (["window", "demote"], Request.demote),
    (["layout", "set", "tall"], Request.layout(.set(.tall))),
    (["layout", "set", "full"], Request.layout(.set(.full))),
    (["layout", "set", "strip"], Request.layout(.set(.strip))),
    (["layout", "next"], Request.layout(.next)),
    (["window", "size", "quarter"], Request.size(.set(.quarter))),
    (["window", "size", "next"], Request.size(.next)),
    (["layout", "ratio", "+0.05"], Request.ratio(0.05)),
    (["layout", "ratio", "-0.05"], Request.ratio(-0.05)),
    (["layout", "ratio", "+1"], Request.ratio(1)),
    (["window", "float", "on"], Request.float(.on)),
    (["window", "float", "off"], Request.float(.off)),
    (["window", "float", "toggle"], Request.float(.toggle)),
    (["tiling", "on"], Request.tiling(.on)),
    (["tiling", "off"], Request.tiling(.off)),
    (["tiling", "toggle"], Request.tiling(.toggle)),
    (["workspace", "retile"], Request.retile),
    (["workspace", "focus", "prev"], Request.workspace(.prev)),
    (["workspace", "focus", "next"], Request.workspace(.next)),
    (["workspace", "focus", "3"], Request.workspace(.number(3))),
    (["window", "move-to-workspace", "next"], Request.moveToWorkspace(.next, follow: false)),
    (
      ["window", "move-to-workspace", "2", "--follow"],
      Request.moveToWorkspace(.number(2), follow: true)
    ),
    (
      ["window", "move-to-workspace", "--follow", "prev"],
      Request.moveToWorkspace(.prev, follow: true)
    ),
    (["display", "focus", "prev"], Request.display(.prev)),
    (["display", "focus", "next"], Request.display(.next)),
    (["display", "focus", "2"], Request.display(.number(2))),
    (["window", "move-to-display", "next"], Request.moveToDisplay(.next, follow: false)),
    (
      ["window", "move-to-display", "2", "--follow"],
      Request.moveToDisplay(.number(2), follow: true)
    ),
    (
      ["window", "move-to-display", "--follow", "prev"], Request.moveToDisplay(.prev, follow: true)
    ),
    (["workspace", "move-to-display", "next"], Request.moveWorkspaceToDisplay(.next)),
    (["workspace", "move-to-display", "2"], Request.moveWorkspaceToDisplay(.number(2))),
  ]

  @Test(arguments: tilingCommands)
  func parsesEveryTilingCommand(arguments: [String], expected: Request) throws {
    #expect(try CommandLineParser.parse(arguments) == Invocation(request: expected))
  }

  @Test(arguments: [
    (["window", "focus"], "window focus takes exactly one argument: next|prev|master"),
    (["window", "focus", "left"], "unknown window focus argument 'left' (use next|prev|master)"),
    (
      ["window", "focus", "next", "prev"],
      "window focus takes exactly one argument: next|prev|master"
    ),
    (["window", "swap"], "window swap takes exactly one argument: next|prev|master"),
    (["window", "swap", "up"], "unknown window swap argument 'up' (use next|prev|master)"),
    (["layout", "set"], "layout set takes exactly one argument: tall|grid|full|strip"),
    (["layout", "set", "wide"], "unknown layout set argument 'wide' (use tall|grid|full|strip)"),
    (["layout", "set", "next"], "unknown layout set argument 'next' (use tall|grid|full|strip)"),
    (["window", "size"], "window size takes exactly one argument: half|full|quarter|next"),
    (["window", "size", "huge"], "unknown window size 'huge' (use half|full|quarter|next)"),
    (["layout", "ratio"], "layout ratio takes exactly one argument, such as +0.05 or -0.05"),
    (["layout", "ratio", "0.05"], "layout ratio must be a signed number such as +0.05 or -0.05"),
    (["layout", "ratio", "+abc"], "layout ratio must be a signed number such as +0.05 or -0.05"),
    (["layout", "ratio", "+inf"], "layout ratio must be a signed number such as +0.05 or -0.05"),
    (["layout", "ratio", "+nan"], "layout ratio must be a signed number such as +0.05 or -0.05"),
    (
      ["layout", "ratio", "+0.05", "+0.05"],
      "layout ratio takes exactly one argument, such as +0.05 or -0.05"
    ),
    (["window", "float"], "window float takes exactly one argument: on|off|toggle"),
    (["window", "float", "yes"], "unknown window float argument 'yes' (use on|off|toggle)"),
    (["tiling"], "tiling takes exactly one argument: on|off|toggle"),
    (["tiling", "maybe"], "unknown tiling argument 'maybe' (use on|off|toggle)"),
    (["workspace", "retile", "now"], "workspace retile takes no arguments"),
    (["workspace", "focus"], "workspace focus takes exactly one argument: prev|next|<n>"),
    (
      ["workspace", "focus", "prev", "next"],
      "workspace focus takes exactly one argument: prev|next|<n>"
    ),
    (
      ["workspace", "focus", "0"],
      "unknown workspace focus argument '0' (use prev|next|<n>, where n starts at 1)"
    ),
    (
      ["workspace", "focus", "left"],
      "unknown workspace focus argument 'left' (use prev|next|<n>, where n starts at 1)"
    ),
    (
      ["workspace", "focus", "down"],
      "unknown workspace focus argument 'down' (use prev|next|<n>, where n starts at 1)"
    ),
    (
      ["window", "move-to-workspace"],
      "window move-to-workspace takes one target (prev|next|<n>) and optionally --follow"
    ),
    (
      ["window", "move-to-workspace", "--follow"],
      "window move-to-workspace takes one target (prev|next|<n>) and optionally --follow"
    ),
    (
      ["window", "move-to-workspace", "1", "2"],
      "window move-to-workspace takes one target (prev|next|<n>) and optionally --follow"
    ),
    (
      ["window", "move-to-workspace", "1", "--follow", "--follow"],
      "window move-to-workspace takes one target (prev|next|<n>) and optionally --follow"
    ),
    (
      ["window", "move-to-workspace", "-1"],
      "unknown window move-to-workspace argument '-1' (use prev|next|<n>, where n starts at 1)"
    ),
    (["display", "focus"], "display focus takes exactly one argument: prev|next|<n>"),
    (["display", "focus", "1", "2"], "display focus takes exactly one argument: prev|next|<n>"),
    (
      ["display", "focus", "0"],
      "unknown display focus argument '0' (use prev|next|<n>, where n starts at 1)"
    ),
    (
      ["display", "focus", "left"],
      "unknown display focus argument 'left' (use prev|next|<n>, where n starts at 1)"
    ),
    (
      ["window", "move-to-display"],
      "window move-to-display takes one target (prev|next|<n>) and optionally --follow"
    ),
    (
      ["window", "move-to-display", "1", "2", "--follow"],
      "window move-to-display takes one target (prev|next|<n>) and optionally --follow"
    ),
    (
      ["window", "move-to-display", "0"],
      "unknown window move-to-display argument '0' (use prev|next|<n>, where n starts at 1)"
    ),
    (
      ["workspace", "move-to-display"],
      "workspace move-to-display takes exactly one argument: prev|next|<n>"
    ),
    (
      ["workspace", "move-to-display", "2", "--follow"],
      "workspace move-to-display takes exactly one argument: prev|next|<n>"
    ),
    (
      ["workspace", "move-to-display", "x"],
      "unknown workspace move-to-display argument 'x' (use prev|next|<n>, where n starts at 1)"
    ),
  ])
  func rejectsBadArgumentsAndNamesTheValidChoices(arguments: [String], message: String) {
    #expect(throws: CommandLineError.usage(message)) {
      try CommandLineParser.parse(arguments)
    }
  }

}
