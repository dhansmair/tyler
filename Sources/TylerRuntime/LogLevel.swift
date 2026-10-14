import OSLog

/// How much goes into tylerd's log file, from the most to the least.
package enum LogLevel: String, CaseIterable, Comparable, Sendable {
  /// Each step: a pointer rest, an AX call.
  case debug
  /// Each decision: a focus asked for, a grab, a press passed on, a notification dropped.
  case info
  /// What a user should know: a tap that was refused, an app given up on.
  case warning
  /// Something failed.
  case error

  package static func < (lhs: Self, rhs: Self) -> Bool {
    allCases.firstIndex(of: lhs) ?? 0 < allCases.firstIndex(of: rhs) ?? 0
  }

  /// The unified log's type for this level.
  var osLogType: OSLogType {
    switch self {
    case .debug: .debug
    case .info: .default
    case .warning, .error: .error
    }
  }
}
