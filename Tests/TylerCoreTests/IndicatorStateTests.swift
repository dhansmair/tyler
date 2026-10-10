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

  @Test func theTitleNumbersTheWorkspacesAndBracketsTheCurrentOne() {
    #expect(text(state(counts: [2, 1, 0, 3], current: 1)) == "1 [2] 3 4  ▥")
    #expect(text(state(counts: [0, 0, 1, 0], current: 0, layout: .full)) == "[1] 2 3 4  ▢")
  }

  @Test func emptyWorkspacesAreFaint() {
    let faint = state(counts: [2, 1, 0, 0], current: 3).title.filter(\.isFaint).map(\.text)
    #expect(faint == ["3"], "the current workspace is never faint, even when empty")
  }

  @Test func theTitleKeepsItsWidthWhileSwitching() {
    let widths = (0..<4).map { text(state(current: $0)).count }
    #expect(Set(widths).count == 1)
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
  func withoutTilingANoticeReplacesTheTitle(tiling: ServerStatus.Tiling, notice: String) {
    let off = state(tiling: tiling)
    #expect(off.title == [IndicatorState.TitlePart("tyler: \(notice)", isFaint: true)])
    #expect(off.layout == nil)
  }

  @Test func theStateIsBuiltFromTheRow() {
    var row = WorkspaceRow(count: 3)
    row[1].insert(WindowID(7))
    row[1].layout = .full
    row.select(1)
    let built = IndicatorState(row: row, tiling: .on)
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

private func text(_ state: IndicatorState) -> String {
  state.title.map(\.text).joined()
}

extension IndicatorState {
  fileprivate func with(layout: LayoutKind, at index: Int) -> IndicatorState {
    var copy = self
    copy.workspaces[index].layout = layout
    return copy
  }
}
