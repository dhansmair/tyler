import Foundation
import Testing
import TylerCore

@testable import TylerConfig

/// `docs/tyler.toml`, the sample config, can't drift from what tylerd reads.
@Suite("Config: the sample file")
struct ConfigSampleTests {
  private let text: String

  init() throws {
    let sample = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("docs/tyler.toml")
    text = try String(contentsOf: sample, encoding: .utf8)
  }

  @Test func everyValueInItIsTheDefault() throws {
    #expect(try Config.parse(text) == Config())
  }

  /// Each setting is set in the file, or (for the tables of apps and displays, which have no
  /// default) shown as a commented-out section; an app's settings in a commented-out example.
  @Test func itNamesEverySetting() throws {
    let document = try TOML.parse(text)
    for name in Config.settingNames {
      if let star = name.range(of: ".*.") {
        let table = name[..<star.lowerBound]
        let key = name[star.upperBound...]
        #expect(
          text.contains("\n# [\(table).") && text.contains("\n# \(key) = "),
          "the sample doesn't show \(name)")
        continue
      }
      let path = name.split(separator: ".").map(String.init)
      let isSet = Self.value(at: path, in: document) != nil
      #expect(isSet || text.contains("\n# [\(name)]\n"), "the sample doesn't show \(name)")
    }
  }

  private static func value(at path: [String], in table: [String: TOMLValue]) -> TOMLValue? {
    guard let first = path.first, let value = table[first] else { return nil }
    guard path.count > 1 else { return value }
    guard case .table(let inner) = value else { return nil }
    return Self.value(at: Array(path.dropFirst()), in: inner)
  }
}
