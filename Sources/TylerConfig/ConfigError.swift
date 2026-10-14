/// Why a config file could not be used.
package enum ConfigError: Error, Equatable, Sendable, CustomStringConvertible {
  case unreadable(String)
  case syntax(TOMLError)
  /// Valid TOML, but not a valid config: an unknown key, a wrong type, a value out of range.
  case invalid(String)

  package var description: String {
    switch self {
    case .unreadable(let reason): "cannot read the file: \(reason)"
    case .syntax(let error): error.description
    case .invalid(let message): message
    }
  }
}
