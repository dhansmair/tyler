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
      ping           check that mwmd is running
      list [--json]  show the windows mwmd is tracking
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
      throw CommandLineError.usage("unknown command '\(command)'")
    }
  }
}
