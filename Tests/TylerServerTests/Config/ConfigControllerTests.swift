import CoreGraphics
import Testing
import TylerConfig
import TylerCore

@testable import TylerServer

@Suite("ConfigController")
struct ConfigControllerTests {
  private static let display = DisplayInfo(
    id: 1, frame: CGRect(x: 0, y: 0, width: 1000, height: 600),
    visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 600))

  private func controller(_ config: Config = Config()) -> ConfigController {
    ConfigController(
      context: ControllerContext(
        registry: WindowRegistry(), displays: [Self.display], config: config))
  }

  @Test func aNewConfigRetilesAndResetsThePointer() {
    var config = Config()
    config.workspaces.count = 6
    var model = Model(rows: DisplayRows(keys: [Self.display.key], configured: [[1, 2, 3, 4]]))
    let decision = controller(config).apply(replacing: Config(), summary: "reloaded", model: &model)
    #expect(model.rows.focused.count == 6)
    #expect(decision.summary == "reloaded")
    #expect(decision.effects == [.applyPointerSettings, .reconcile()])
  }

  @Test func anUnknownSettingIsRefused() {
    #expect(
      throws: Refusal.error("unknown setting 'nonsense' (`tyler config get` lists every setting)")
    ) {
      try controller().value("nonsense")
    }
  }

  @Test func aSettingIsCheckedAsTheFileIs() {
    #expect(throws: Refusal.self) { try controller().setting("gaps.inner", to: "\"wide\"") }
  }
}
