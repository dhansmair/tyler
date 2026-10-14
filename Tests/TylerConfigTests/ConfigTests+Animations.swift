import Testing

@testable import TylerConfig

@Suite("Config: animations")
struct ConfigAnimationsTests {
  @Test func parsesAnimations() throws {
    let config = try Config.parse(
      """
      [animations]
      swap = 0
      drag-preview = 120
      """)
    #expect(config.animations == Config.Animations(swap: 0, dragPreview: 120))
  }

  @Test(arguments: [
    (
      "[animations]\nswap = -1", "animations.swap must be a whole number of milliseconds, 0 to 1000"
    ),
    (
      "[animations]\ndrag-preview = 1001",
      "animations.drag-preview must be a whole number of milliseconds, 0 to 1000"
    ),
  ])
  func rejectsDurationsOutOfRange(text: String, message: String) {
    #expect(throws: ConfigError.invalid(message)) {
      try Config.parse(text)
    }
  }
}
