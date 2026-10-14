import Testing
import TylerCore

@testable import TylerConfig

@Suite("Config: layouts")
struct ConfigLayoutsTests {
  @Test func layoutsDefaultToTallAndFullStartingWithTall() throws {
    #expect(try Config.parse("").layouts == Config.Layouts(cycle: [.tall, .full], initial: .tall))
  }

  @Test func parsesLayouts() throws {
    let config = try Config.parse(
      """
      [layouts]
      cycle = ["full", "strip", "tall"]
      default = "strip"
      """)
    #expect(config.layouts == Config.Layouts(cycle: [.full, .strip, .tall], initial: .strip))
  }

  @Test(arguments: [
    ("layouts = 1", "layouts must be a table: write [layouts] and put cycle and default below it"),
    ("[layouts]\norder = []", "unknown setting 'layouts.order' (use cycle or default)"),
    (
      "[layouts]\ncycle = []",
      "layouts.cycle must list layouts from \"tall\", \"grid\", \"full\", \"strip\", like [\"tall\", \"full\"]"
    ),
    (
      "[layouts]\ncycle = \"tall\"",
      "layouts.cycle must list layouts from \"tall\", \"grid\", \"full\", \"strip\", like [\"tall\", \"full\"]"
    ),
    (
      "[layouts]\ncycle = [\"tall\", \"wide\"]",
      "layouts.cycle must list layouts from \"tall\", \"grid\", \"full\", \"strip\", like [\"tall\", \"full\"]"
    ),
    ("[layouts]\ncycle = [\"tall\", \"tall\"]", "layouts.cycle lists tall twice"),
    (
      "[layouts]\ndefault = \"wide\"",
      "layouts.default must be one of \"tall\", \"grid\", \"full\", \"strip\""
    ),
    (
      "[layouts]\ndefault = 1",
      "layouts.default must be one of \"tall\", \"grid\", \"full\", \"strip\""
    ),
  ])
  func rejectsInvalidLayouts(text: String, message: String) {
    #expect(throws: ConfigError.invalid(message)) {
      try Config.parse(text)
    }
  }
}
