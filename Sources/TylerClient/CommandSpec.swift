/// One `tyler` command: how it reads in the usage text, and how its arguments are parsed.
struct CommandSpec: Sendable {
  /// The command's words: one for a command about tylerd itself (`start`, `tiling`), or a noun and
  /// a verb (`window focus`) for one that acts on a window, workspace, layout or display.
  let name: String
  /// The arguments as the usage text shows them, such as `next|prev|master`.
  let arguments: String
  let summary: String
  let parse: @Sendable (_ arguments: [String]) throws -> Invocation

  /// The thing the command acts on (`window` in `window focus`), or `nil` for a one-word command.
  var noun: String? {
    let words = name.split(separator: " ")
    return words.count == 2 ? String(words[0]) : nil
  }

  /// What the command does to its noun (`focus` in `window focus`), or the whole one-word name.
  var verb: String { String(name.split(separator: " ").last ?? "") }
}
