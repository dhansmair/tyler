import MWMCore

public enum CommandLineError: Error, Equatable {
  case usage(String)
}

/// Parses `mwm` argv (without the program name) into a `Request`.
public enum CommandLineParser {
  public static let usage = """
    usage: mwm <command>

    commands:
      ping    check that mwmd is running
    """

  public static func parse(_ arguments: [String]) throws -> Request {
    guard let command = arguments.first else {
      throw CommandLineError.usage("missing command")
    }
    let rest = arguments.dropFirst()
    switch command {
    case "ping":
      guard rest.isEmpty else {
        throw CommandLineError.usage("ping takes no arguments")
      }
      return .ping
    default:
      throw CommandLineError.usage("unknown command '\(command)'")
    }
  }
}

/// Renders a `Response` for the terminal.
public enum ResponseFormatter {
  /// Returns the text to print and whether the command succeeded.
  public static func format(_ response: Response) -> (text: String, success: Bool) {
    switch response {
    case .pong:
      return ("pong", true)
    case .error(let message):
      return (message, false)
    }
  }
}
