import CoreGraphics
import Testing
import TylerConfig
import TylerCore
import TylerTestSupport

@testable import TylerServer

@Suite("WorkspaceController")
struct WorkspaceControllerTests {
  private static let display = DisplayInfo(
    id: 1, frame: CGRect(x: 0, y: 0, width: 1000, height: 600),
    visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 600))

  /// Windows 1 and 2 on workspace 1, window 3 on workspace 2; window 1 focused.
  private func setUp() -> (WorkspaceController, Model) {
    var registry = WindowRegistry()
    registry.replaceAll((1...3).map { makeWindow(id: $0, isFocused: $0 == 1) })
    var model = Model(rows: DisplayRows(keys: [Self.display.key], configured: [[1, 2]]))
    model.rows.focused[0].append(WindowID(1))
    model.rows.focused[0].append(WindowID(2))
    model.rows.focused[1].append(WindowID(3))
    model.bookkeeping.seen = [WindowID(1), WindowID(2), WindowID(3)]
    let context = ControllerContext(registry: registry, displays: [Self.display], config: Config())
    return (WorkspaceController(context: context), model)
  }

  @Test func switchingSlidesThenFocuses() throws {
    var (controller, model) = setUp()
    let decision = try controller.switchWorkspace(.next, model: &model)
    #expect(model.rows.focused.currentIndex == 1)
    #expect(decision.summary == "workspace 2")
    #expect(decision.effects.first == .endSlideOrSwipe)
    #expect(decision.effects.last == .focusCurrentWorkspace)
    #expect(decision.effects.contains { if case .animate = $0 { true } else { false } })
  }

  @Test func aWindowAlreadyThereIsNotMoved() {
    var (controller, model) = setUp()
    #expect(throws: Refusal.message("already on workspace 1")) {
      try controller.moveToWorkspace(.number(1), follow: false, model: &model)
    }
  }

  @Test func aMissingWorkspaceListsTheOnesThatExist() {
    var (controller, model) = setUp()
    #expect(throws: Refusal.error("workspace 7 does not exist (use 1 to 2)")) {
      try controller.switchWorkspace(.number(7), model: &model)
    }
  }

  @Test(arguments: [([1, 2, 3, 4], "1 to 4"), ([5, 6, 9], "5, 6, 9"), ([7], "7")])
  func theErrorNamesTheWorkspacesThereAre(numbers: [Int], named: String) {
    #expect(WorkspaceController.describe(numbers) == named)
  }

  @Test func aSwitchDuringADragEndsTheDragFirst() throws {
    var registry = WindowRegistry()
    registry.replaceAll((1...3).map { makeWindow(id: $0, isFocused: $0 == 1) })
    var model = Model(rows: DisplayRows(keys: [Self.display.key], configured: [[1, 2]]))
    model.rows.focused[0].append(WindowID(1))
    model.rows.focused[1].append(WindowID(3))
    model.bookkeeping.seen = [WindowID(1), WindowID(3)]
    let context = ControllerContext(
      registry: registry, displays: [Self.display], config: Config(),
      dragSession: DragSession(windowID: WindowID(1)))
    let effects = WorkspaceController(context: context).focusChanged(
      to: WindowID(3), isEcho: false, model: &model)
    let forgot = try #require(effects.firstIndex(of: .forgetDrag))
    let slid = try #require(effects.firstIndex { if case .animate = $0 { true } else { false } })
    #expect(effects.first == .endSlideOrSwipe)
    #expect(forgot < slid)
  }
}
