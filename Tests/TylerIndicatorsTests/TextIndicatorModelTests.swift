import Testing
import TylerCore

@testable import TylerIndicators

@Suite("Text indicator title and menu")
struct TextIndicatorModelTests {
  @Test func theTitleNumbersTheWorkspacesAndBracketsTheCurrentOne() {
    #expect(text(snapshot(counts: [2, 1, 0, 3], current: 1)) == "1 [2] 3 4  ▥")
    #expect(text(snapshot(counts: [0, 0, 1, 0], current: 0, layout: .full)) == "[1] 2 3 4  ▢")
  }

  @Test func emptyWorkspacesAreFaint() {
    let faint = TextTitle(snapshot(counts: [2, 1, 0, 0], current: 3)).parts.filter(\.isFaint)
    #expect(faint.map(\.text) == ["3"], "the current workspace is never faint, even when empty")
  }

  @Test func theTitleKeepsItsWidthWhileSwitching() {
    let widths = (0..<4).map { text(snapshot(current: $0)).count }
    #expect(Set(widths).count == 1)
  }

  @Test func theLayoutIsTheCurrentWorkspaces() {
    var mixed = snapshot(current: 1)
    mixed.row[1].layout = .full
    #expect(mixed.currentLayout == .full)
    #expect(snapshot().currentLayout == .tall)
  }

  @Test(arguments: [
    (ServerStatus.Tiling.off, "tiling off"), (.waitingForPermission, "no access"),
  ])
  func withoutTilingANoticeReplacesTheTitle(tiling: ServerStatus.Tiling, notice: String) {
    let off = snapshot(tiling: tiling)
    #expect(TextTitle(off).parts == [TextTitle.Part("tyler: \(notice)", isFaint: true)])
    #expect(off.currentLayout == nil)
  }

  @Test func theTitleAndMenuIgnoreFocusAndRatio() {
    let before = snapshot(counts: [2, 1, 0, 0])
    var after = before
    after.row.current.focus(.next)
    after.row.current.adjustRatio(by: 0.1)
    #expect(after != before)
    #expect(TextTitle(after) == TextTitle(before))
    #expect(IndicatorMenu(after) == IndicatorMenu(before))
  }

  @Test func theMenuListsWorkspacesThenLayoutAndTiling() {
    #expect(
      IndicatorMenu(snapshot(counts: [2, 1, 0], current: 1)).items == [
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
      IndicatorMenu(snapshot(tiling: .off)).items == [
        .action(title: "Tiling: off", isChecked: false, request: .tiling(.on))
      ])
    #expect(
      IndicatorMenu(snapshot(tiling: .waitingForPermission)).items == [
        .note("Waiting for Accessibility permission")
      ])
  }
}

private func text(_ snapshot: IndicatorSnapshot) -> String {
  TextTitle(snapshot).parts.map(\.text).joined()
}
