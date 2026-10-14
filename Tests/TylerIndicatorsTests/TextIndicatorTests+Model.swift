import Testing
import TylerCore
import TylerProtocol

@testable import TylerIndicators

@Suite("Text indicator title and menu")
struct TextIndicatorModelTests {
  @Test func theTitleNumbersTheWorkspacesAndBracketsTheCurrentOne() {
    #expect(text(snapshot(counts: [2, 1, 0, 3], current: 1)) == "1 [2] 3 4  ▥")
    #expect(text(snapshot(counts: [0, 0, 1, 0], current: 0, layout: .full)) == "[1] 2 3 4  ▢")
  }

  @Test func theTitleAndMenuShowTheRowsOwnNumbers() {
    let second = snapshot(counts: [1, 0, 2], current: 1, numbers: [5, 6, 9])
    #expect(text(second) == "5 [6] 9  ▥")
    let menu = IndicatorMenu(second).items.prefix(3)
    #expect(
      Array(menu) == [
        .action(
          title: "Workspace 5  (1 window)", isChecked: false,
          choice: .request(.workspace(.number(5)))),
        .action(title: "Workspace 6", isChecked: true, choice: .request(.workspace(.number(6)))),
        .action(
          title: "Workspace 9  (2 windows)", isChecked: false,
          choice: .request(.workspace(.number(9)))),
      ])
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
          title: "Workspace 1  (2 windows)", isChecked: false,
          choice: .request(.workspace(.number(1)))),
        .action(
          title: "Workspace 2  (1 window)", isChecked: true,
          choice: .request(.workspace(.number(2)))),
        .action(title: "Workspace 3", isChecked: false, choice: .request(.workspace(.number(3)))),
        .separator,
        .action(title: "Layout: tall → grid", isChecked: false, choice: .request(.layout(.next))),
        .action(title: "Tiling: on", isChecked: true, choice: .request(.tiling(.off))),
        .separator,
        .action(title: "Reload config", isChecked: false, choice: .request(.reload)),
        .action(title: "Open config", isChecked: false, choice: .request(.configEdit)),
        .action(title: "Quit tyler", isChecked: false, choice: .quit),
      ])
  }

  @Test func theMenuNamesTheNextLayoutOfTheCycle() {
    var configured = snapshot(layout: .full)
    #expect(
      IndicatorMenu(configured).items.contains(
        .action(
          title: "Layout: full → tall", isChecked: false, choice: .request(.layout(.next)))))
    configured.layoutCycle = [.full, .strip]
    #expect(
      IndicatorMenu(configured).items.contains(
        .action(
          title: "Layout: full → strip", isChecked: false, choice: .request(.layout(.next)))))
  }

  @Test func theMenuWithoutTilingOffersOnlyWhatWorks() {
    #expect(
      IndicatorMenu(snapshot(tiling: .off)).items.dropLast(4) == [
        .action(title: "Tiling: off", isChecked: false, choice: .request(.tiling(.on)))
      ])
    #expect(
      IndicatorMenu(snapshot(tiling: .waitingForPermission)).items.dropLast(4) == [
        .note("Waiting for Accessibility permission")
      ])
  }

  @Test(arguments: [ServerStatus.Tiling.on, .off, .waitingForPermission])
  func theMenuEndsWithTheConfigAndQuitting(tiling: ServerStatus.Tiling) {
    let items = IndicatorMenu(snapshot(tiling: tiling)).items
    #expect(
      Array(items.suffix(4)) == [
        .separator,
        .action(title: "Reload config", isChecked: false, choice: .request(.reload)),
        .action(title: "Open config", isChecked: false, choice: .request(.configEdit)),
        .action(title: "Quit tyler", isChecked: false, choice: .quit),
      ])
  }
}

private func text(_ snapshot: IndicatorSnapshot) -> String {
  TextTitle(snapshot).parts.map(\.text).joined()
}
