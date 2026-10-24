import OSLog

/// Where the lines of `TylerLog` go beyond the unified log: in tylerd, stderr, which goes to
/// `~/.tyler/tyler.log` (`tyler start` sends it there, or `LogFile` opens it). Thread-safe, since
/// the IPC server logs off the main thread.
package final class LogOutput: Sendable {
  /// The one tylerd writes to.
  package static let shared = LogOutput()

  private struct State {
    var level = LogLevel.warning
    var sink: (@Sendable (String) -> Void)?
  }

  private let state = OSAllocatedUnfairLock(initialState: State())

  package init() {}

  /// The least level written to the sink; the unified log gets every line regardless.
  package var level: LogLevel {
    get { state.withLock { $0.level } }
    set { state.withLock { $0.level = newValue } }
  }

  /// Receives each line at or above `level`, without a trailing newline; `nil` writes nowhere.
  package func setSink(_ sink: (@Sendable (String) -> Void)?) {
    state.withLock { $0.sink = sink }
  }

  /// Whether a line at `level` would reach the sink, so a caller can skip building it.
  func accepts(_ level: LogLevel) -> Bool {
    state.withLock { $0.sink != nil && level >= $0.level }
  }

  func write(_ line: String) {
    let sink = state.withLock { $0.sink }
    sink?(line)
  }

  /// One line of the log: the local date and time to the millisecond (as macOS's own `NSLog` lines
  /// in the same file have it), the level, the category, the text.
  /// `2026-10-12 18:47:02.123 warning pointer   mouse button interceptor turned off - mid-gesture`
  package static func line(
    _ message: String, level: LogLevel, category: String, at date: Date,
    in timeZone: TimeZone = .current
  ) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let parts = calendar.dateComponents(
      [.year, .month, .day, .hour, .minute, .second, .nanosecond], from: date)
    let time = String(
      format: "%04d-%02d-%02d %02d:%02d:%02d.%03d", parts.year ?? 0, parts.month ?? 0,
      parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0,
      (parts.nanosecond ?? 0) / 1_000_000)
    let padded = { (text: String, width: Int) in
      text.padding(toLength: max(width, text.count), withPad: " ", startingAt: 0)
    }
    return "\(time) \(padded(level.rawValue, 7)) \(padded(category, 9)) \(message)"
  }
}
