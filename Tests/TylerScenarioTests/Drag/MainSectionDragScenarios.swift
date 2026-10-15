import CoreGraphics
import Testing

/// Dragging a window between the master section and the stack of `tall`: the section it is
/// dropped on makes room for it, and the one it leaves closes up.
@Suite("Move by drag: tall's master section")
@MainActor
struct MainSectionDragScenarios {
  /// Windows 1 and 2 in the master section, 3 alone in the stack.
  private func twoMains() async -> Scenario {
    let scenario = await Scenario(workspaces: [1: [1, 2, 3]], layout: .tall)
    await scenario.focus(2)
    await scenario.command("window promote")
    return scenario
  }

  @Test func aStackedWindowDroppedOnTheMainColumnJoinsTheMainSection() async {
    let scenario = await Scenario(workspaces: [1: [1, 2, 3]], layout: .tall)
    // From the lower right to the lower half of the master's slot.
    await scenario.drag(3, by: CGVector(dx: -1000, dy: 200))
    #expect(scenario.list(1) == [1, 3, 2])
    #expect(scenario.frame(of: 1) == scenario.rect(.leftTop))
    #expect(scenario.frame(of: 3) == scenario.rect(.leftBottom))
    #expect(scenario.frame(of: 2) == scenario.rect(.rightHalf))
  }

  @Test func aMainDroppedOnTheStackJoinsTheStack() async {
    let scenario = await twoMains()
    // From the upper left to the lower half of the stack.
    await scenario.drag(1, by: CGVector(dx: 809, dy: 852))
    #expect(scenario.list(1) == [2, 3, 1])
    #expect(scenario.frame(of: 2) == scenario.rect(.leftHalf))
    #expect(scenario.frame(of: 3) == scenario.rect(.rightTop))
    #expect(scenario.frame(of: 1) == scenario.rect(.rightBottom))
  }

  @Test func aMainDroppedWithinTheMainSectionStaysAMain() async {
    let scenario = await twoMains()
    // From the lower left to the upper left.
    await scenario.drag(2, by: CGVector(dx: -191, dy: -414))
    #expect(scenario.list(1) == [2, 1, 3])
    #expect(scenario.frame(of: 2) == scenario.rect(.leftTop))
    #expect(scenario.frame(of: 1) == scenario.rect(.leftBottom))
    #expect(scenario.frame(of: 3) == scenario.rect(.rightHalf))
  }
}
