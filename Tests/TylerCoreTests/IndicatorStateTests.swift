import Testing

@testable import TylerCore

@Suite("Indicator state")
struct IndicatorStateTests {
  private func state(
    counts: [Int] = [2, 1, 0, 0], current: Int = 0, layout: LayoutKind = .tall,
    tiling: ServerStatus.Tiling = .on
  ) -> IndicatorState {
    IndicatorState(
      workspaces: counts.map { IndicatorState.Workspace(windowCount: $0, layout: layout) },
      currentIndex: current, tiling: tiling)
  }

  @Test func dotsMarkTheCurrentOccupiedAndEmptyWorkspaces() {
    #expect(
      state(counts: [2, 1, 0, 3], current: 2).dots == [.occupied, .occupied, .current, .occupied])
    #expect(state(counts: [0, 0, 1, 0], current: 0).dots == [.current, .empty, .occupied, .empty])
  }

  @Test func theLayoutIsTheCurrentWorkspaces() {
    var mixed = state(current: 1)
    mixed.workspaces[1].layout = .full
    #expect(mixed.layout == .full)
    #expect(state().layout == .tall)
  }

  @Test(arguments: [
    (ServerStatus.Tiling.off, "tiling off"), (.waitingForPermission, "no access"),
  ])
  func withoutTilingANoticeReplacesDotsAndLayout(tiling: ServerStatus.Tiling, notice: String) {
    let off = state(tiling: tiling)
    #expect(off.notice == notice)
    #expect(off.dots.isEmpty)
    #expect(off.layout == nil)
  }

  @Test func theStateIsBuiltFromTheStack() {
    var stack = WorkspaceStack(count: 3)
    stack[1].insert(WindowID(7))
    stack[1].layout = .full
    stack.select(1)
    let built = IndicatorState(stack: stack, tiling: .on)
    #expect(
      built == state(counts: [0, 1, 0], current: 1, layout: .tall).with(layout: .full, at: 1))
  }

  @Test func theMenuListsWorkspacesThenLayoutAndTiling() {
    #expect(
      state(counts: [2, 1, 0], current: 1).menu == [
        .action(
          title: "Workspace 1  (2 windows)", isChecked: false, request: .workspace(.number(1))),
        .action(title: "Workspace 2  (1 window)", isChecked: true, request: .workspace(.number(2))),
        .action(title: "Workspace 3", isChecked: false, request: .workspace(.number(3))),
        .separator,
        .action(title: "Layout: tall → full", isChecked: false, request: .layout(.next)),
        .action(title: "Tiling: on", isChecked: true, request: .tiling(.off)),
      ])
  }

  @Test func theMenuWithoutTilingOffersOnlyWhatWorks() {
    #expect(
      state(tiling: .off).menu == [
        .action(title: "Tiling: off", isChecked: false, request: .tiling(.on))
      ])
    #expect(
      state(tiling: .waitingForPermission).menu == [.note("Waiting for Accessibility permission")])
  }
}

extension IndicatorState {
  fileprivate func with(layout: LayoutKind, at index: Int) -> IndicatorState {
    var copy = self
    copy.workspaces[index].layout = layout
    return copy
  }
}
