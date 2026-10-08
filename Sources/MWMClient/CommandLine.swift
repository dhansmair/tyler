import MWMCore

public enum CommandLineError: Error, Equatable {
  case usage(String)
}

/// How the client should print the server's reply.
public enum OutputFormat: Equatable, Sendable {
  case text
  case json
}

/// A parsed command line: what to ask the server, and how to show the answer.
public struct Invocation: Equatable, Sendable {
  public var request: Request
  public var format: OutputFormat

  public init(request: Request, format: OutputFormat = .text) {
    self.request = request
    self.format = format
  }
}

/// Parses `mwm` argv (without the program name) into an `Invocation`.
public enum CommandLineParser {
  public static let usage = """
    usage: mwm <command>

    commands:
      ping                           check that mwmd is running
      list [--json]                  show the windows mwmd is tracking
      focus next|prev|master         move focus within the tiling list
      swap next|prev|master          swap the focused window with another slot
      layout tall|full|next          choose the layout
      ratio +0.05|-0.05              widen or narrow the master column
      float toggle                   float the focused window, or tile it again
      tiling on|off|toggle           start or stop tiling (windows stay where they are)
      retile                         put every tiled window back into its slot
    """

  public static func parse(_ arguments: [String]) throws -> Invocation {
    guard let command = arguments.first else {
      throw CommandLineError.usage("missing command")
    }
    let rest = Array(arguments.dropFirst())
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
