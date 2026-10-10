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

/// Parses `tyler` argv (without the program name) into an `Invocation`.
public enum CommandLineParser {
  public static let usage = """
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
      layout tall|full|next          choose the layout
      ratio +0.05|-0.05              widen or narrow the master column
      float toggle                   float the focused window, or tile it again
      tiling on|off|toggle           start or stop tiling (off unparks hidden windows)
      retile                         put every tiled window back into its slot
      workspace up|down|<n>          switch to another workspace (up and down wrap)
      move-to-workspace up|down|<n> [--follow]
                                     send the focused window to another workspace
    """

  public static func parse(_ arguments: [String]) throws -> Invocation {
    guard let command = arguments.first else {
      throw CommandLineError.usage("missing command")
    }
    let rest = Array(arguments.dropFirst())
    if let daemonCommand = DaemonCommand(rawValue: command) {
      try requireNoArguments(rest, for: command)
      return Invocation(action: .daemon(daemonCommand))
    }
    switch command {
    case "ping":
      guard rest.isEmpty else {
        throw CommandLineError.usage("ping takes no arguments")
      }
      return Invocation(request: .ping)
    case "list":
      switch rest {
      case []:
        return Invocation(request: .list)
      case ["--json"]:
        return Invocation(request: .list, format: .json)
      default:
        throw CommandLineError.usage("list only accepts --json")
      }
    case "reload":
      try requireNoArguments(rest, for: command)
      return Invocation(request: .reload)
    default:
      return try parseTilingCommand(command, rest)
    }
  }

  private static func parseTilingCommand(_ command: String, _ rest: [String]) throws -> Invocation {
    switch command {
    case "retile":
      try requireNoArguments(rest, for: command)
      return Invocation(request: .retile)
    case "focus":
      return Invocation(request: .focus(try parseTarget(rest, for: command)))
    case "swap":
      return Invocation(request: .swap(try parseTarget(rest, for: command)))
    case "layout":
      return Invocation(request: .layout(try parseLayout(rest)))
    case "ratio":
      return Invocation(request: .ratio(try parseRatio(rest)))
    case "float":
      guard rest == ["toggle"] else {
        throw CommandLineError.usage("float takes exactly one argument: toggle")
      }
      return Invocation(request: .toggleFloat)
    case "tiling":
      let mode = try parseChoice(rest, for: command, choices: TilingMode.allCases)
      return Invocation(request: .tiling(mode))
    default:
      return try workspaceCommand(command, rest)
    }
  }

  private static func workspaceCommand(_ command: String, _ rest: [String]) throws -> Invocation {
    switch command {
    case "workspace":
      guard rest.count == 1 else {
        throw CommandLineError.usage("workspace takes exactly one argument: up|down|<n>")
      }
      return Invocation(request: .workspace(try parseTarget(rest[0], for: command)))
    case "move-to-workspace":
      return try parseMoveToWorkspace(rest)
    default:
      throw CommandLineError.usage("unknown command '\(command)'")
    }
  }

  // MARK: - Arguments

  private static func requireNoArguments(_ arguments: [String], for command: String) throws {
    guard arguments.isEmpty else {
      throw CommandLineError.usage("\(command) takes no arguments")
    }
  }

  private static func parseTarget(_ arguments: [String], for command: String) throws -> ListTarget {
    try parseChoice(arguments, for: command, choices: ListTarget.allCases)
  }

  private static func parseLayout(_ arguments: [String]) throws -> LayoutChoice {
    guard arguments.count == 1, let name = arguments.first else {
      throw CommandLineError.usage("layout takes exactly one argument: \(layoutNames)")
    }
    if name == "next" { return .next }
    guard let kind = LayoutKind(rawValue: name) else {
      throw CommandLineError.usage("unknown layout '\(name)' (use \(layoutNames))")
    }
    return .set(kind)
  }

  private static var layoutNames: String {
    (LayoutKind.allCases.map(\.rawValue) + ["next"]).joined(separator: "|")
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

  /// `up`, `down`, or a workspace number from 1. The upper bound is the server's to check.
  private static func parseTarget(_ text: String, for command: String) throws -> WorkspaceTarget {
    switch text {
    case "up": return .up
    case "down": return .down
    default:
      guard let number = Int(text), number >= 1 else {
        throw CommandLineError.usage(
          "unknown \(command) argument '\(text)' (use up|down|<n>, where n starts at 1)")
      }
      return .number(number)
    }
  }

  private static func parseMoveToWorkspace(_ arguments: [String]) throws -> Invocation {
    let follow = arguments.contains("--follow")
    let targets = arguments.filter { $0 != "--follow" }
    guard targets.count == 1, arguments.count == targets.count + (follow ? 1 : 0) else {
      throw CommandLineError.usage(
        "move-to-workspace takes one target (up|down|<n>) and optionally --follow")
    }
    let target = try parseTarget(targets[0], for: "move-to-workspace")
    return Invocation(request: .moveToWorkspace(target, follow: follow))
  }

  private static func parseChoice<Choice: RawRepresentable & Sendable>(
    _ arguments: [String],
    for command: String,
    choices: [Choice]
  ) throws -> Choice where Choice.RawValue == String {
    let names = choices.map(\.rawValue).joined(separator: "|")
    guard arguments.count == 1, let name = arguments.first else {
      throw CommandLineError.usage("\(command) takes exactly one argument: \(names)")
    }
    guard let choice = choices.first(where: { $0.rawValue == name }) else {
      throw CommandLineError.usage("unknown \(command) argument '\(name)' (use \(names))")
    }
    return choice
  }
}
