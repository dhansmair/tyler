import Foundation
import Testing
import os

@testable import TylerRuntime

@Suite("TylerLog")
struct TylerLogTests {
  /// Collects what reaches the sink, behind a lock as the sink may be called from any thread.
  final class Lines: Sendable {
    private let lines = OSAllocatedUnfairLock(initialState: [String]())
    var all: [String] { lines.withLock { $0 } }
    func append(_ line: String) { lines.withLock { $0.append(line) } }
  }

  private func log(level: LogLevel) -> (TylerLog, Lines) {
    let output = LogOutput()
    let lines = Lines()
    output.setSink { lines.append($0) }
    output.level = level
    return (TylerLog(category: "test", output: output), lines)
  }

  @Test func linesBelowTheLevelStayOutOfTheFile() {
    let (log, lines) = log(level: .warning)
    log.debug("d")
    log.info("i")
    log.warning("w")
    log.error("e")
    #expect(lines.all.map { $0.hasSuffix(" w") || $0.hasSuffix(" e") } == [true, true])
    #expect(lines.all.count == 2)
  }

  @Test func debugTakesEverything() {
    let (log, lines) = log(level: .debug)
    log.debug("d")
    log.info("i")
    #expect(lines.all.count == 2)
  }

  @Test func aLineBelowTheLevelIsNeverBuilt() {
    let (log, _) = log(level: .warning)
    let built = Lines()
    log.debug(
      {
        built.append("built")
        return "d"
      }())
    #expect(built.all.isEmpty)
  }

  @Test func withoutASinkNothingIsWritten() {
    let output = LogOutput()
    output.level = .debug
    #expect(!output.accepts(.error))
  }

  @Test func aLineHasTheTimeLevelCategoryAndText() {
    let date = Date(timeIntervalSince1970: 3723.0456)  // 1970-01-01 01:02:03.045 UTC
    let line = LogOutput.line(
      "window moving started - #7", level: .info, category: "pointer", at: date,
      in: TimeZone(identifier: "UTC") ?? .current)
    #expect(line == "1970-01-01 01:02:03.045 info    pointer   window moving started - #7")
  }

  @Test func levelsAreOrderedFromDebugToError() {
    #expect(LogLevel.allCases.sorted() == [.debug, .info, .warning, .error])
  }
}
