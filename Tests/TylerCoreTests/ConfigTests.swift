import Foundation
import Testing

@testable import TylerCore

@Suite("Config")
struct ConfigTests {
  @Test(arguments: ["", "# nothing set yet\n", "[gaps]"])
  func missingSettingsUseTheDefaults(text: String) throws {
    #expect(try Config.parse(text) == Config())
    #expect(Config().gaps == Config.Gaps(inner: 0, outer: 0))
  }

  @Test func parsesGaps() throws {
    let config = try Config.parse(
      """
      [gaps]
      inner = 8
      outer = 12
      """)
    #expect(config.gaps == Config.Gaps(inner: 8, outer: 12))
  }

  @Test func parsesGapsWrittenAsDottedKeys() throws {
    #expect(try Config.parse("gaps.outer = 4").gaps == Config.Gaps(inner: 0, outer: 4))
  }

  @Test(arguments: [
    ("gap = 8", "unknown setting 'gap'"),
    ("[gaps]\ninnr = 8", "unknown setting 'gaps.innr' (use inner or outer)"),
    ("gaps = 8", "gaps must be a table: write [gaps] and put inner and outer below it"),
    ("[gaps]\ninner = -1", "gaps.inner must be a whole number of points, 0 or more"),
    ("[gaps]\nouter = 2.5", "gaps.outer must be a whole number of points, 0 or more"),
    ("[gaps]\ninner = \"8\"", "gaps.inner must be a whole number of points, 0 or more"),
  ])
  func rejectsInvalidSettings(text: String, message: String) {
    #expect(throws: ConfigError.invalid(message)) {
      try Config.parse(text)
    }
  }

  @Test func syntaxErrorsKeepTheirLine() {
    let error = ConfigError.syntax(TOMLError(line: 2, message: "expected '=' after the key"))
    #expect(throws: error) {
      try Config.parse("[gaps]\ninner 8")
    }
    #expect(error.description == "line 2: expected '=' after the key")
  }

  // MARK: - Reading the file

  private func temporaryPath() -> String {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("tyler-\(UUID().uuidString).toml").path
  }

  @Test func aMissingFileReadsAsNoConfig() throws {
    #expect(try ConfigSource.file(at: temporaryPath()).read() == nil)
  }

  @Test func readsTheFile() throws {
    let path = temporaryPath()
    try "[gaps]\ninner = 6\n".write(toFile: path, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(atPath: path) }

    let source = ConfigSource.file(at: path)
    #expect(source.path == path)
    #expect(try source.read() == Config(gaps: Config.Gaps(inner: 6)))
  }

  @Test func aBrokenFileThrows() throws {
    let path = temporaryPath()
    try "gap = 8\n".write(toFile: path, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(atPath: path) }

    #expect(throws: ConfigError.invalid("unknown setting 'gap'")) {
      try ConfigSource.file(at: path).read()
    }
  }
}
