/// How `tyler logs` runs `tail`. Only a terminal follows the log: a pipe gets the end of the file
/// and is done, so a script or an agent doesn't wait forever.
package enum LogViewing {
  private static let lineCount = "50"

  /// `-F`, not `-f`: each `tyler start` or `restart` renames the log and opens a new one, and `-f`
  /// would stay on the old file.
  package static func tailArguments(path: String, isTerminal: Bool) -> [String] {
    ["tail", "-n", lineCount] + (isTerminal ? ["-F"] : []) + [path]
  }
}
