import Foundation
import Testing

@testable import TylerRuntime

@Suite("Version")
struct TylerVersionTests {
  /// The changelog's latest entry (`## 0.1.0 (unreleased)` or `## 0.1.0 (2026-10-20)`) names the
  /// version tyler reports, so a release can't forget either.
  @Test func theChangelogsLatestEntryIsTheCurrentVersion() throws {
    let changelog = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("CHANGELOG.md")
    let text = try String(contentsOf: changelog, encoding: .utf8)
    let heading = try #require(text.split(separator: "\n").first { $0.hasPrefix("## ") })
    #expect(
      heading.dropFirst(3).split(separator: " ").first.map(String.init) == TylerVersion.current)
  }

  @Test func theVersionIsSemantic() {
    let parts = TylerVersion.current.split(separator: ".")
    #expect(parts.count == 3)
    #expect(parts.allSatisfy { Int($0) != nil })
  }
}
