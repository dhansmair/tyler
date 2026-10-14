import TylerCore
import TylerProtocol

/// Parses `tyler` argv (without the program name) into an `Invocation`. Every command is one
/// entry in `commands`, which also builds the usage text; `docs/manual.md` has a section for each
/// (a test checks). Commands are grouped by what they act on, `tyler <noun> <verb>` (see
/// `devdocs/design.md`).
package enum CommandLineParser {
  static let commands: [CommandSpec] =
    [
      daemon(.start, "start tylerd in the background"),
      daemon(.stop, "stop tylerd (windows go back where they were)"),
      daemon(.restart, "stop tylerd and start it again, for example after a rebuild"),
      daemon(.status, "show whether tylerd is running, and which build"),
      simple("ping", .ping, "check that tylerd is running"),
      CommandSpec(
        name: "tiling", arguments: choices(TilingMode.allCases),
        summary: "start or stop tiling (off unparks hidden windows)"
      ) { Invocation(request: .tiling(try parseChoice($0, for: "tiling"))) },
    ] + windowCommands + workspaceCommands + layoutCommands + displayCommands + configCommands
    + [debugAt, debugWindows]

  package static let usage = """
    usage: tyler <command> [arguments]
           tyler <window|workspace|layout|display|config|debug> <command> [arguments]
           tyler --version

    commands:
    \(usageLines)
    """

  package static func parse(_ arguments: [String]) throws -> Invocation {
    if arguments == ["--version"] { return Invocation(action: .printVersion) }
    guard let name = arguments.first else {
      throw CommandLineError.usage("missing command")
    }
    let nounCommands = commands.filter { $0.noun == name }
    guard !nounCommands.isEmpty else {
      guard let command = commands.first(where: { $0.noun == nil && $0.name == name }) else {
        throw CommandLineError.usage("unknown command '\(name)'")
      }
      return try command.parse(Array(arguments.dropFirst()))
    }
    let verbs = nounCommands.map(\.verb).joined(separator: ", ")
    guard arguments.count >= 2 else {
      throw CommandLineError.usage("missing \(name) command (use \(verbs))")
    }
    guard let command = nounCommands.first(where: { $0.verb == arguments[1] }) else {
      throw CommandLineError.usage("unknown \(name) command '\(arguments[1])' (use \(verbs))")
    }
    return try command.parse(Array(arguments.dropFirst(2)))
  }

  // MARK: - Commands

  /// Where a command's summary starts in the usage text; a longer command line puts its summary
  /// on the next line.
  private static let summaryColumn = 33

  /// One line per command, with a blank line before each noun's commands.
  private static var usageLines: String {
    var lines: [String] = []
    for (index, command) in commands.enumerated() {
      if index > 0, command.noun != nil, command.noun != commands[index - 1].noun {
        lines.append("")
      }
      lines.append(usageLine(command))
    }
    return lines.joined(separator: "\n")
  }

  private static func usageLine(_ command: CommandSpec) -> String {
    let line =
      "  " + ([command.name, command.arguments].filter { !$0.isEmpty }.joined(separator: " "))
    guard line.count < summaryColumn else {
      return line + "\n" + String(repeating: " ", count: summaryColumn) + command.summary
    }
    return line + String(repeating: " ", count: summaryColumn - line.count) + command.summary
  }

  private static func daemon(_ command: DaemonCommand, _ summary: String) -> CommandSpec {
    CommandSpec(name: command.rawValue, arguments: "", summary: summary) { arguments in
      try requireNoArguments(arguments, for: command.rawValue)
      return Invocation(action: .daemon(command))
    }
  }

  /// A command that takes no arguments and sends `request`.
  private static func simple(_ name: String, _ request: Request, _ summary: String) -> CommandSpec {
    CommandSpec(name: name, arguments: "", summary: summary) { arguments in
      try requireNoArguments(arguments, for: name)
      return Invocation(request: request)
    }
  }

  private static func choices<Choice: RawRepresentable>(_ cases: [Choice]) -> String
  where Choice.RawValue == String {
    cases.map(\.rawValue).joined(separator: "|")
  }

  private static let workspaceTargets = "prev|next|<n>"
  private static let displayTargets = "prev|next|<n>"

  // MARK: - Arguments

  private static func requireNoArguments(_ arguments: [String], for command: String) throws {
    guard arguments.isEmpty else {
      throw CommandLineError.usage("\(command) takes no arguments")
    }
  }

  /// One argument: a `Choice` by name, or `next` (`nil`).
  private static func parseNameOrNext<Choice: CaseIterable & RawRepresentable>(
    _ arguments: [String], for command: String
  ) throws -> Choice? where Choice.RawValue == String {
    let names = namesOrNext(Choice.self)
    guard arguments.count == 1, let name = arguments.first else {
      throw CommandLineError.usage("\(command) takes exactly one argument: \(names)")
    }
    if name == "next" { return nil }
    guard let choice = Choice(rawValue: name) else {
      throw CommandLineError.usage("unknown \(command) '\(name)' (use \(names))")
    }
    return choice
  }

  private static func namesOrNext<Choice: CaseIterable & RawRepresentable>(
    _: Choice.Type
  ) -> String where Choice.RawValue == String {
    choices(Array(Choice.allCases)) + "|next"
  }

  /// A signed step such as `+0.05` or `-0.1`. The sign is required so `layout ratio 0.05` can't
  /// be mistaken for "set the ratio to 0.05".
  private static func parseRatio(_ arguments: [String]) throws -> Double {
    guard arguments.count == 1, let text = arguments.first else {
      throw CommandLineError.usage(
        "layout ratio takes exactly one argument, such as +0.05 or -0.05")
    }
    guard text.hasPrefix("+") || text.hasPrefix("-"), let value = Double(text), value.isFinite
    else {
      throw CommandLineError.usage("layout ratio must be a signed number such as +0.05 or -0.05")
    }
    return value
  }

  /// `prev`, `next`, or a workspace number from 1. The upper bound is the server's to check.
  private static func parseTarget(_ text: String, for command: String) throws -> WorkspaceTarget {
    switch text {
    case "prev": return .prev
    case "next": return .next
    default:
      guard let number = Int(text), number >= 1 else {
        throw CommandLineError.usage(
          "unknown \(command) argument '\(text)' (use \(workspaceTargets), where n starts at 1)")
      }
      return .number(number)
    }
  }

  /// `prev`, `next`, or a display number from 1. The upper bound is the server's to check.
  private static func parseDisplay(_ text: String, for command: String) throws -> DisplayTarget {
    switch text {
    case "prev": return .prev
    case "next": return .next
    default:
      guard let number = Int(text), number >= 1 else {
        throw CommandLineError.usage(
          "unknown \(command) argument '\(text)' (use \(displayTargets), where n starts at 1)")
      }
      return .number(number)
    }
  }

  private static func parseMoveToWorkspace(_ arguments: [String]) throws -> Invocation {
    let command = "window move-to-workspace"
    let (text, follow) = try parseFollow(arguments, for: command, targets: workspaceTargets)
    return Invocation(
      request: .moveToWorkspace(try parseTarget(text, for: command), follow: follow))
  }

  private static func parseMoveToDisplay(_ arguments: [String]) throws -> Invocation {
    let command = "window move-to-display"
    let (text, follow) = try parseFollow(arguments, for: command, targets: displayTargets)
    return Invocation(request: .moveToDisplay(try parseDisplay(text, for: command), follow: follow))
  }

  /// One target and, before or after it, an optional `--follow`.
  private static func parseFollow(
    _ arguments: [String], for command: String, targets: String
  ) throws -> (target: String, follow: Bool) {
    let follow = arguments.contains("--follow")
    let others = arguments.filter { $0 != "--follow" }
    guard others.count == 1, arguments.count == others.count + (follow ? 1 : 0) else {
      throw CommandLineError.usage(
        "\(command) takes one target (\(targets)) and optionally --follow")
    }
    return (others[0], follow)
  }

  private static func parseChoice<Choice: CaseIterable & RawRepresentable>(
    _ arguments: [String], for command: String
  ) throws -> Choice where Choice.RawValue == String {
    let choices = Array(Choice.allCases)
    let names = Self.choices(choices)
    guard arguments.count == 1, let name = arguments.first else {
      throw CommandLineError.usage("\(command) takes exactly one argument: \(names)")
    }
    guard let choice = choices.first(where: { $0.rawValue == name }) else {
      throw CommandLineError.usage("unknown \(command) argument '\(name)' (use \(names))")
    }
    return choice
  }
}

// MARK: - Commands by noun

extension CommandLineParser {
  private static let windowCommands = [
    CommandSpec(
      name: "window list", arguments: "[--json]", summary: "show the windows tylerd is tracking"
    ) { arguments in
      switch arguments {
      case []: Invocation(request: .list)
      case ["--json"]: Invocation(request: .list, format: .json)
      default: throw CommandLineError.usage("window list only accepts --json")
      }
    },
    CommandSpec(
      name: "window focus", arguments: choices(ListTarget.allCases),
      summary: "move focus within the tiling list"
    ) { Invocation(request: .focus(try parseChoice($0, for: "window focus"))) },
    CommandSpec(
      name: "window swap", arguments: choices(ListTarget.allCases),
      summary: "swap the focused window with another slot"
    ) { Invocation(request: .swap(try parseChoice($0, for: "window swap"))) },
    CommandSpec(
      name: "window float", arguments: choices(FloatMode.allCases),
      summary: "float the focused window, or tile it again"
    ) { Invocation(request: .float(try parseChoice($0, for: "window float"))) },
    simple("window close", .close, "close the focused window"),
    CommandSpec(
      name: "window size", arguments: namesOrNext(WindowSize.self),
      summary: "size the focused window in the strip layout"
    ) {
      Invocation(
        request: .size(try parseNameOrNext($0, for: "window size").map(SizeChoice.set) ?? .next))
    },
    CommandSpec(
      name: "window move-to-workspace", arguments: "\(workspaceTargets) [--follow]",
      summary: "send the focused window to another workspace", parse: parseMoveToWorkspace),
    CommandSpec(
      name: "window move-to-display", arguments: "\(displayTargets) [--follow]",
      summary: "send the focused window to another display", parse: parseMoveToDisplay),
  ]

  private static let workspaceCommands = [
    CommandSpec(
      name: "workspace focus", arguments: workspaceTargets,
      summary: "switch to another workspace (prev and next wrap)"
    ) { arguments in
      let command = "workspace focus"
      guard arguments.count == 1 else {
        throw CommandLineError.usage("\(command) takes exactly one argument: \(workspaceTargets)")
      }
      return Invocation(request: .workspace(try parseTarget(arguments[0], for: command)))
    },
    CommandSpec(
      name: "workspace move-to-display", arguments: displayTargets,
      summary: "move the current workspace to another display"
    ) { arguments in
      let command = "workspace move-to-display"
      guard arguments.count == 1 else {
        throw CommandLineError.usage("\(command) takes exactly one argument: \(displayTargets)")
      }
      return Invocation(
        request: .moveWorkspaceToDisplay(try parseDisplay(arguments[0], for: command)))
    },
    simple("workspace retile", .retile, "put every tiled window back into its slot"),
  ]

  private static let layoutCommands = [
    CommandSpec(
      name: "layout set", arguments: choices(LayoutKind.allCases),
      summary: "choose the current workspace's layout"
    ) { Invocation(request: .layout(.set(try parseChoice($0, for: "layout set")))) },
    simple("layout next", .layout(.next), "switch to the next layout of layouts.cycle"),
    CommandSpec(
      name: "layout ratio", arguments: "+0.05|-0.05", summary: "widen or narrow the master column"
    ) { Invocation(request: .ratio(try parseRatio($0))) },
  ]

  private static let displayCommands = [displayFocus]

  private static let displayFocus = CommandSpec(
    name: "display focus", arguments: displayTargets,
    summary: "focus another display (prev and next wrap)"
  ) { arguments in
    let command = "display focus"
    guard arguments.count == 1 else {
      throw CommandLineError.usage("\(command) takes exactly one argument: \(displayTargets)")
    }
    return Invocation(request: .display(try parseDisplay(arguments[0], for: command)))
  }

  /// Settings are named as in the config file (`gaps.inner`); the server checks names and values.
  private static let configCommands = [
    CommandSpec(
      name: "config get", arguments: "[<setting>]", summary: "show a setting, or every setting"
    ) { arguments in
      guard arguments.count <= 1 else {
        throw CommandLineError.usage(
          "config get takes at most one argument: a setting's name, such as gaps.inner")
      }
      return Invocation(request: .configGet(arguments.first))
    },
    CommandSpec(
      name: "config set", arguments: "<setting> <value>",
      summary: "change a setting until tylerd stops or reloads"
    ) { arguments in
      guard arguments.count >= 2 else {
        throw CommandLineError.usage(
          "config set takes a setting's name and a value, such as gaps.inner 8")
      }
      // The shell splits `[1, 2]` into two words; put them back together.
      let value = arguments.dropFirst().joined(separator: " ")
      return Invocation(request: .configSet(name: arguments[0], value: value))
    },
    simple("config reload", .reload, "read the config file again (drops what set changed)"),
    CommandSpec(
      name: "config edit", arguments: "", summary: "open the config file in your editor"
    ) {
      try requireNoArguments($0, for: "config edit")
      return Invocation(action: .editConfig)
    },
  ]
}
