import TylerCore

public enum CommandLineError: Error, Equatable {
  case usage(String)
}

/// How the client should print the server's reply.
public enum OutputFormat: Equatable, Sendable {
  case text
  case json
}

/// Commands that manage the `tylerd` process instead of asking it to do something.
public enum DaemonCommand: String, CaseIterable, Sendable {
  case start
  case stop
  case restart
  case status
}

/// A parsed command line: what to do, and how to show the answer.
public struct Invocation: Equatable, Sendable {
  public enum Action: Equatable, Sendable {
    /// Send one request to the running server.
    case send(Request)
    /// Start, stop or inspect the server process.
    case daemon(DaemonCommand)
  }

  public var action: Action
  public var format: OutputFormat

  public init(request: Request, format: OutputFormat = .text) {
    self.init(action: .send(request), format: format)
  }

  public init(action: Action, format: OutputFormat = .text) {
    self.action = action
    self.format = format
  }
}

/// One `tyler` command: how it reads in the usage text, and how its arguments are parsed.
struct CommandSpec: Sendable {
  let name: String
  /// The arguments as the usage text shows them, such as `next|prev|master`.
  let arguments: String
  let summary: String
  let parse: @Sendable (_ arguments: [String]) throws -> Invocation
}

/// Parses `tyler` argv (without the program name) into an `Invocation`. Every command is one
/// entry in `commands`, which also builds the usage text; `docs/manual.md` has a section for each
/// (a test checks).
public enum CommandLineParser {
  static let commands: [CommandSpec] = [
    daemon(.start, "start tylerd in the background"),
    daemon(.stop, "stop tylerd (windows go back where they were)"),
    daemon(.restart, "stop tylerd and start it again, for example after a rebuild"),
    daemon(.status, "show whether tylerd is running, and which build"),
    simple("ping", .ping, "check that tylerd is running"),
    CommandSpec(
      name: "list", arguments: "[--json]", summary: "show the windows tylerd is tracking"
    ) { arguments in
      switch arguments {
      case []: Invocation(request: .list)
      case ["--json"]: Invocation(request: .list, format: .json)
      default: throw CommandLineError.usage("list only accepts --json")
      }
    },
    simple("reload", .reload, "read the config file again and apply it"),
    CommandSpec(
      name: "focus", arguments: choices(ListTarget.allCases),
      summary: "move focus within the tiling list"
    ) { Invocation(request: .focus(try parseChoice($0, for: "focus"))) },
    CommandSpec(
      name: "swap", arguments: choices(ListTarget.allCases),
      summary: "swap the focused window with another slot"
    ) { Invocation(request: .swap(try parseChoice($0, for: "swap"))) },
    CommandSpec(
      name: "layout", arguments: namesOrNext(LayoutKind.self), summary: "choose the layout"
    ) {
      Invocation(
        request: .layout(try parseNameOrNext($0, for: "layout").map(LayoutChoice.set) ?? .next))
    },
    CommandSpec(
      name: "size", arguments: namesOrNext(WindowSize.self),
      summary: "size the focused window in the strip layout"
    ) {
      Invocation(request: .size(try parseNameOrNext($0, for: "size").map(SizeChoice.set) ?? .next))
    },
    CommandSpec(
      name: "ratio", arguments: "+0.05|-0.05", summary: "widen or narrow the master column"
    ) { Invocation(request: .ratio(try parseRatio($0))) },
    CommandSpec(
      name: "float", arguments: "toggle", summary: "float the focused window, or tile it again"
    ) { arguments in
      guard arguments == ["toggle"] else {
        throw CommandLineError.usage("float takes exactly one argument: toggle")
      }
      return Invocation(request: .toggleFloat)
    },
    CommandSpec(
      name: "tiling", arguments: choices(TilingMode.allCases),
      summary: "start or stop tiling (off unparks hidden windows)"
    ) { Invocation(request: .tiling(try parseChoice($0, for: "tiling"))) },
    simple("retile", .retile, "put every tiled window back into its slot"),
    CommandSpec(
      name: "workspace", arguments: workspaceTargets,
      summary: "switch to another workspace (prev and next wrap)"
    ) { arguments in
      guard arguments.count == 1 else {
        throw CommandLineError.usage("workspace takes exactly one argument: \(workspaceTargets)")
      }
      return Invocation(request: .workspace(try parseTarget(arguments[0], for: "workspace")))
    },
    CommandSpec(
      name: "move-to-workspace", arguments: "\(workspaceTargets) [--follow]",
      summary: "send the focused window to another workspace", parse: parseMoveToWorkspace),
  ]

  public static let usage = """
    usage: tyler <command>

    commands:
    \(commands.map(usageLine).joined(separator: "\n"))
    """

  public static func parse(_ arguments: [String]) throws -> Invocation {
    guard let name = arguments.first else {
      throw CommandLineError.usage("missing command")
    }
    guard let command = commands.first(where: { $0.name == name }) else {
      throw CommandLineError.usage("unknown command '\(name)'")
    }
    return try command.parse(Array(arguments.dropFirst()))
  }

  // MARK: - Commands

  /// Where a command's summary starts in the usage text; a longer command line puts its summary
  /// on the next line.
  private static let summaryColumn = 33

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

  /// A signed step such as `+0.05` or `-0.1`. The sign is required so `ratio 0.05` can't be
  /// mistaken for "set the ratio to 0.05".
  private static func parseRatio(_ arguments: [String]) throws -> Double {
    guard arguments.count == 1, let text = arguments.first else {
      throw CommandLineError.usage("ratio takes exactly one argument, such as +0.05 or -0.05")
    }
    guard text.hasPrefix("+") || text.hasPrefix("-"), let value = Double(text), value.isFinite
    else {
      throw CommandLineError.usage("ratio must be a signed number such as +0.05 or -0.05")
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

  private static func parseMoveToWorkspace(_ arguments: [String]) throws -> Invocation {
    let follow = arguments.contains("--follow")
    let targets = arguments.filter { $0 != "--follow" }
    guard targets.count == 1, arguments.count == targets.count + (follow ? 1 : 0) else {
      throw CommandLineError.usage(
        "move-to-workspace takes one target (\(workspaceTargets)) and optionally --follow")
    }
    let target = try parseTarget(targets[0], for: "move-to-workspace")
    return Invocation(request: .moveToWorkspace(target, follow: follow))
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
