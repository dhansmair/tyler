import CoreGraphics
import Testing
import TylerConfig
import TylerCore
import TylerTestSupport

@testable import TylerServer

@Suite("DragController")
struct DragControllerTests {
  private static let display = DisplayInfo(
    id: 1, frame: CGRect(x: 0, y: 0, width: 1000, height: 600),
    visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 600))
  /// Where tall puts windows 1 and 2.
  private static let left = CGRect(x: 0, y: 0, width: 500, height: 600)
  private static let right = CGRect(x: 500, y: 0, width: 500, height: 600)

  /// Windows 1 and 2 in their slots, side by side.
  private func setUp(buttonDown: Bool = true) -> (DragController, Model) {
    var registry = WindowRegistry()
    registry.replaceAll([
      makeWindow(id: 1, frame: Self.left, isFocused: true), makeWindow(id: 2, frame: Self.right),
    ])
    var model = Model(rows: DisplayRows(keys: [Self.display.key], configured: [[1, 2]]))
    model.rows.focused.current.append(WindowID(1))
    model.rows.focused.current.append(WindowID(2))
    let context = ControllerContext(
      registry: registry, displays: [Self.display], config: Config(),
      isPrimaryButtonDown: buttonDown)
    return (DragController(context: context), model)
  }

  @Test func aWindowMovedWithoutTheButtonIsNoDrag() {
    var (controller, model) = setUp(buttonDown: false)
    let moved = makeWindow(id: 1, frame: Self.left.offsetBy(dx: 40, dy: 0))
    #expect(controller.windowUpdated(moved, from: Self.left, session: nil, model: &model) == nil)
  }

  @Test func aWindowLeavingItsSlotStartsADragThatIsNoResize() throws {
    var (controller, model) = setUp()
    let moved = makeWindow(id: 1, frame: Self.left.offsetBy(dx: 40, dy: 0))
    let step = try #require(
      controller.windowUpdated(moved, from: Self.left, session: nil, model: &model))
    #expect(step.session.windowID == WindowID(1))
    #expect(!step.session.isResize)
    #expect(step.pendingFrame == nil)
  }

  @Test func aWindowChangingSizeIsAResizeForTheLayoutToFollow() throws {
    var (controller, model) = setUp()
    let resized = makeWindow(id: 1, frame: CGRect(x: 0, y: 0, width: 600, height: 600))
    let step = try #require(
      controller.windowUpdated(resized, from: Self.left, session: nil, model: &model))
    #expect(step.session.isResize)
    #expect(step.pendingFrame == resized.frame)
  }

  @Test func aWindowSmallerThanItsSlotMovedKeepingItsSizeIsNoResize() throws {
    var (controller, model) = setUp()
    let before = CGRect(origin: Self.left.origin, size: CGSize(width: 500, height: 400))
    let moved = makeWindow(id: 1, frame: before.offsetBy(dx: 40, dy: 0))
    let step = try #require(
      controller.windowUpdated(moved, from: before, session: nil, model: &model))
    #expect(!step.session.isResize)
  }
}
