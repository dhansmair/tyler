import CoreGraphics
import Testing
import TylerConfig
import TylerCore
import TylerTestSupport

@testable import TylerServer

@Suite("SyncController")
struct SyncControllerTests {
  private static let display = DisplayInfo(
    id: 1, frame: CGRect(x: 0, y: 0, width: 1000, height: 600),
    visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 600))

  private func context(
    crossing: Set<WindowID> = [], isSettling: Bool = false
  ) -> ControllerContext {
    var registry = WindowRegistry()
    registry.replaceAll([makeWindow(id: 1), makeWindow(id: 2)])
    return ControllerContext(
      registry: registry, displays: [Self.display], config: Config(),
      crossingWindows: crossing, isSettling: isSettling)
  }

  private func model() -> Model {
    Model(rows: DisplayRows(keys: [Self.display.key], configured: [[1, 2]]))
  }

  @Test func newWindowsJoinTheCurrentWorkspace() {
    var model = model()
    let decision = SyncController(context: context()).sync(model: &model)
    #expect(model.rows.focused.current.windows == [WindowID(1), WindowID(2)])
    #expect(decision.changedCurrent)
    #expect(model.bookkeeping.seen == [WindowID(1), WindowID(2)])
  }

  @Test func nothingChangesWhileTheDisplaysSettle() {
    var model = model()
    let before = model
    let decision = SyncController(context: context(isSettling: true)).sync(model: &model)
    #expect(model == before)
    #expect(decision.effects.isEmpty)
  }

  @Test func aCrossingWindowOnItsWorkspacesDisplayIsReleased() {
    var model = model()
    model.rows.focused.current.append(WindowID(1))
    let decision = SyncController(context: context(crossing: [WindowID(1)])).sync(model: &model)
    #expect(decision.effects.contains(.releaseCrossings([WindowID(1)])))
  }

  /// Worked out when the sync decides, so a switch the same decision makes afterwards on that
  /// display can't change which windows it lays out.
  @Test func anotherDisplaysNewWindowGetsItsSlotThere() throws {
    let other = DisplayInfo(
      id: 2, frame: CGRect(x: 1000, y: 0, width: 1000, height: 600),
      visibleFrame: CGRect(x: 1000, y: 0, width: 1000, height: 600))
    var registry = WindowRegistry()
    registry.replaceAll([
      makeWindow(id: 1), makeWindow(id: 2, frame: CGRect(x: 1100, y: 100, width: 300, height: 200)),
    ])
    let context = ControllerContext(
      registry: registry, displays: [Self.display, other], config: Config())
    var model = Model(
      rows: DisplayRows(keys: [Self.display.key, other.key], configured: [[1, 2], [3, 4]]))
    let outcome = SyncController(context: context).sync(model: &model)
    #expect(
      outcome.effects.contains(
        .place([Placement(id: WindowID(2), frame: other.visibleFrame)])))
  }
}
