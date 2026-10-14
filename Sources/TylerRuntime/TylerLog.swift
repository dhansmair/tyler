import Foundation
import OSLog

/// tyler's logger for one category: every line goes to the unified log (`Logger`, subsystem
/// `tyler`), and those at or above `LogOutput.level` also to its sink, so they can be read in
/// `~/.tyler/tyler.log` without admin rights. Debug lines are built, and reach the unified log too,
/// only while `log.level` is `debug`: they are the frequent ones.
package struct TylerLog: Sendable {
  package let category: String
  private let logger: Logger
  private let output: LogOutput

  package init(category: String, output: LogOutput = .shared) {
    self.category = category
    self.logger = Logger(subsystem: "tyler", category: category)
    self.output = output
  }

  package func debug(_ message: @autoclosure () -> String) { log(.debug, message) }
  package func info(_ message: @autoclosure () -> String) { log(.info, message) }
  package func warning(_ message: @autoclosure () -> String) { log(.warning, message) }
  package func error(_ message: @autoclosure () -> String) { log(.error, message) }

  private func log(_ level: LogLevel, _ message: () -> String) {
    let toFile = output.accepts(level)
    guard toFile || level > .debug else { return }
    let text = message()
    // tyler's lines hold window numbers and app names, which the unified log would otherwise hide
    // as private. Never titles: they hold what the user reads, such as a browser tab's page.
    logger.log(level: level.osLogType, "\(text, privacy: .public)")
    if toFile {
      output.write(LogOutput.line(text, level: level, category: category, at: Date()))
    }
  }
}
