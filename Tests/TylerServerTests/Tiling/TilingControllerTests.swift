import CoreGraphics
import Testing
import TylerConfig
import TylerCore
import TylerTestSupport

@testable import TylerServer

@Suite("TilingController")
struct TilingControllerTests {
  private static let display = DisplayInfo(
    id: 1, frame: CGRect(x: 0, y: 0, width: 1000, height: 600),
    visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 600))

  /// Windows 1 and 2 tiled on workspace 1, window 1 focused.
  private func setUp(isRunning: Bool = true) -> (TilingController, Model) {
    var registry = WindowRegistry()
    registry.replaceAll([makeWindow(id: 1, isFocused: true), makeWindow(id: 2)])
    var model = Model(rows: DisplayRows(keys: [Self.display.key], configured: [[1, 2]]))
    model.rows.focused.current.append(WindowID(1))
    model.rows.focused.current.append(WindowID(2))
    model.bookkeeping.seen = [WindowID(1), WindowID(2)]
    let context = ControllerContext(
      registry: registry, displays: [Self.display], config: Config(), isRunning: isRunning)
    return (TilingController(context: context), model)
  }

  @Test func floatingTakesTheWindowOutOfTheListAndSlidesTheRestIntoPlace() throws {
    var (controller, model) = setUp()
    let decision = try controller.setFloat(.on, model: &model)
    #expect(model.bookkeeping.floated == [WindowID(1)])
    #expect(model.rows.focused.current.windows == [WindowID(2)])
    let fullScreen = Placement(id: WindowID(2), frame: Self.display.visibleFrame)
    guard case .animate(let retile) = decision.effects.last else {
      Issue.record("the window left re-tiles with an animation: \(decision.effects)")
      return
    }
    #expect(retile.finals == [fullScreen])
  }

  @Test func askingForTheStateAWindowIsInChangesNothing() {
    var (controller, model) = setUp()
    #expect(throws: Refusal.message("already tiled")) {
      try controller.setFloat(.off, model: &model)
    }
  }

  @Test func closingClosesTheFocusedWindow() throws {
    let (controller, _) = setUp()
    #expect(try controller.close().effects == [.close(WindowID(1))])
  }

  @Test func closingNeedsAFocusedWindow() {
    let context = ControllerContext(
      registry: WindowRegistry(), displays: [Self.display], config: Config(), isRunning: true)
    #expect(throws: Refusal.error("no focused window")) {
      try TilingController(context: context).close()
    }
  }

  @Test func beforePermissionTilingOffIsOnlyRecorded() {
    var (controller, model) = setUp(isRunning: false)
    let decision = controller.setTiling(.off, model: &model)
    #expect(!model.tilingEnabled)
    #expect(decision.effects.isEmpty)
    #expect(decision.summary?.hasPrefix("tiling off once Accessibility permission") == true)
  }
}
