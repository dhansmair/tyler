/// A syntax error in a TOML document, with the 1-based line it was found on.
package struct TOMLError: Error, Equatable, Sendable, CustomStringConvertible {
  package let line: Int
  package let message: String

  package init(line: Int, message: String) {
    self.line = line
    self.message = message
  }

  package var description: String { "line \(line): \(message)" }
}
