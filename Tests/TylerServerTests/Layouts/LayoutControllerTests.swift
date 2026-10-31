import CoreGraphics
import Testing
import TylerConfig
import TylerCore
import TylerTestSupport

@testable import TylerServer

/// The layout commands decided on their own: the model in, effects out, nothing moved.
@Suite("LayoutController")
struct LayoutControllerTests {
  private static let display = DisplayInfo(
    id: 1, frame: CGRect(x: 0, y: 0, width: 1000, height: 600),
    visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 600))

  /// Windows 1 to 3 on workspace 1 in `layout`, window `focused` focused.
  private func setUp(
    _ layout: LayoutKind = .tall, focused: UInt32 = 1
  ) -> (LayoutController, Model) {
    var registry = WindowRegistry()
    registry.replaceAll((1...3).map { makeWindow(id: $0, isFocused: $0 == focused) })
    var rows = DisplayRows(keys: [Self.display.key], configured: [[1, 2]], newLayout: layout)
    for raw in 1...3 as ClosedRange<UInt32> { rows.focused.current.append(WindowID(raw)) }
    rows.focused.current.setFocus(WindowID(focused))
    let context = ControllerContext(registry: registry, displays: [Self.display], config: Config())
    return (LayoutController(context: context), Model(rows: rows))
  }

  @Test func choosingALayoutLaysTheWorkspaceOut() {
    var (controller, model) = setUp()
    let decision = controller.setLayout(.set(.grid), model: &model)
    #expect(model.rows.focused.current.layout == .grid)
    #expect(decision.summary == "layout grid")
    #expect(
      decision.effects == [
        .reconcile(), .showLayoutNotice(.grid, over: Self.display.visibleFrame),
      ])
  }

  @Test func theGridRefusesARatio() {
    var (controller, model) = setUp(.grid)
    #expect(throws: Refusal.message("grid has no master ratio")) {
      try controller.adjustRatio(by: 0.05, model: &model)
    }
  }

  @Test func aSizeSetInTallWaitsForTheStrip() throws {
    var (controller, model) = setUp()
    let decision = try controller.setSize(.set(.full), model: &model)
    #expect(model.rows.focused.current.layoutStates.strip.size(of: WindowID(1)) == .full)
    #expect(decision.summary == "size full (used by the strip layout)")
    #expect(decision.effects == [.reconcile()])
  }

  @Test func aSizeThatMovesTheStripsViewScrollsIt() throws {
    var (controller, model) = setUp(.strip, focused: 2)
    let decision = try controller.setSize(.set(.full), model: &model)
    #expect(decision.summary == "size full")
    guard case .animate(let scroll) = try #require(decision.effects.first),
      decision.effects.count == 1
    else {
      Issue.record("expected one scroll, got \(decision.effects)")
      return
    }
    #expect(scroll.finals.contains { $0.id == WindowID(2) })
  }
}
