import CoreGraphics
import TylerCore

/// The `debug` commands, for finding problems: their output may change in any release.
extension CommandLineParser {
  static let debugAt = CommandSpec(
    name: "debug at", arguments: "[<x> <y>] [--json]",
    summary: "what tylerd sees and does at a point"
  ) { arguments in
    let format: OutputFormat = arguments.last == "--json" ? .json : .text
    let words = format == .json ? Array(arguments.dropLast()) : arguments
    if words.isEmpty { return Invocation(request: .debugAt(nil), format: format) }
    guard words.count == 2, let pointX = Double(words[0]), let pointY = Double(words[1]) else {
      throw CommandLineError.usage(
        "debug at takes a point in screen coordinates, such as 300 400, or nothing for the pointer")
    }
    return Invocation(request: .debugAt(CGPoint(x: pointX, y: pointY)), format: format)
  }

  static let debugWindows = CommandSpec(
    name: "debug windows", arguments: "[--json]",
    summary: "where tylerd's picture of the windows differs from macOS's"
  ) { arguments in
    switch arguments {
    case []: Invocation(request: .debugWindows)
    case ["--json"]: Invocation(request: .debugWindows, format: .json)
    default: throw CommandLineError.usage("debug windows only accepts --json")
    }
  }
}
