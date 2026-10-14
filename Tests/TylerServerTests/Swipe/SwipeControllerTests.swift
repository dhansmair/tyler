import CoreGraphics
import Testing
import TylerConfig
import TylerCore
import TylerTestSupport

@testable import TylerServer

@Suite("SwipeController")
struct SwipeControllerTests {
  private static let display = DisplayInfo(
    id: 1, frame: CGRect(x: 0, y: 0, width: 1000, height: 600),
    visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 600))
  private static let middle = CGPoint(x: 500, y: 300)

  /// Window 1 on workspace 1 of 3.
  private func setUp(_ config: Config = Config()) -> (SwipeController, Model) {
    var registry = WindowRegistry()
    registry.replaceAll([makeWindow(id: 1, isFocused: true)])
    var model = Model(rows: DisplayRows(keys: [Self.display.key], configured: [[1, 2, 3]]))
    model.rows.focused.current.append(WindowID(1))
    model.bookkeeping.seen = [WindowID(1)]
    let context = ControllerContext(registry: registry, displays: [Self.display], config: config)
    return (SwipeController(context: context), model)
  }

  @Test func aSwipeOnARowMovesItsNeighbours() {
    var (controller, model) = setUp()
    let session = controller.begin(at: Self.middle, model: &model).session
    guard case .workspaceRow = session?.target else {
      Issue.record("expected a swipe along the row, got \(String(describing: session?.target))")
      return
    }
  }

  @Test func noSwipeWhileSwipingIsOff() {
    var config = Config()
    config.gestures.swipe = false
    var (controller, model) = setUp(config)
    #expect(controller.begin(at: Self.middle, model: &model).session == nil)
  }

  @Test func aFlickSettlesOnTheNextWorkspaceAndFocusesIt() throws {
    var (controller, model) = setUp()
    var session = try #require(controller.begin(at: Self.middle, model: &model).session)
    session.move(travel: -0.1, distance: Config().gestures.swipeDistance)
    let effects = controller.end(session, velocity: -10, model: &model)
    #expect(model.rows.focused.currentIndex == 1)
    #expect(effects.last == .focusCurrentWorkspace)
  }
}
