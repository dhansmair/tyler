import CoreGraphics
import Testing

@testable import TylerCore

private let half = WindowSize.half
private let full = WindowSize.full
private let quarter = WindowSize.quarter

@Suite("Strip layout: columns")
struct StripColumnsTests {
  @Test(arguments: [
    ([half, half, half], [[0], [1], [2]], [1, 1, 1]),
    ([quarter, quarter, half], [[0, 1], [2]], [1, 1]),
    ([quarter, half, quarter], [[0], [1], [2]], [1, 1, 1]),
    ([quarter, quarter, quarter], [[0, 1], [2]], [1, 1]),
    ([full, quarter, quarter, quarter, quarter], [[0], [1, 2], [3, 4]], [2, 1, 1]),
    ([], [], []),
  ])
  func windowsArePackedIntoColumnsInListOrder(
    sizes: [WindowSize], columns: [[Int]], widths: [Int]
  ) {
    let packed = StripColumns(sizes: sizes)
    #expect(packed.columns == columns)
    #expect(packed.widths == widths)
  }

  @Test(arguments: [
    ([half, half, half], 0, 0..<2),
    ([half, half, half], 2, 2..<3),
    ([half, full, half], 0, 0..<1),
    ([half, full, half], 1, 1..<2),
    ([full, full], 0, 0..<1),
  ])
  func theViewShowsTheWholeColumnsThatFit(sizes: [WindowSize], start: Int, visible: Range<Int>) {
    #expect(StripColumns(sizes: sizes).visible(from: start) == visible)
  }

  @Test(arguments: [
    (0, Int?(1), 0),  // already in view
    (0, 2, 1),  // one column to the right: just far enough
    (0, 3, 2),
    (2, 0, 0),  // to the left: it becomes the leftmost
    (3, 3, 2),  // the last column alone would leave empty space after it
    (0, nil, 0),
    (9, nil, 2),  // a start past the end comes back
  ])
  func scrollingShowsTheFocusedColumnWithTheLeastMovement(
    previous: Int, focused: Int?, start: Int
  ) {
    let columns = StripColumns(sizes: [half, half, half, half])
    #expect(columns.fittedStart(previous: previous, focused: focused) == start)
  }

  @Test func aFullColumnIsShownOnItsOwn() {
    let columns = StripColumns(sizes: [half, full, half])
    #expect(columns.fittedStart(previous: 0, focused: 1) == 1)
    #expect(columns.fittedStart(previous: 0, focused: 2) == 2, "the full one can't share the view")
  }

  @Test(arguments: [
    ([half, half, half, half], [0, 1, 2]),
    ([half, full, half], [0, 1, 2]),
    ([half, half], [0]),
    ([full], [0]),
    ([], []),
  ])
  func theViewCanStartAtEveryColumnThatLeavesNoSpaceAfterTheEnd(
    sizes: [WindowSize], starts: [Int]
  ) {
    #expect(StripColumns(sizes: sizes).starts == starts)
  }
}

@Suite("Strip layout: frames")
struct StripLayoutTests {
  private let area = CGRect(x: 0, y: 0, width: 1000, height: 600)

  private func frames(
    _ sizes: [WindowSize], firstVisible: Int = 0, in area: CGRect? = nil,
    gaps: LayoutGaps = LayoutGaps()
  ) -> [CGRect] {
    StripLayout().frames(
      for: LayoutInput(count: sizes.count, sizes: sizes, firstVisible: firstVisible),
      in: area ?? self.area, gaps: gaps)
  }

  @Test func noWindowsGiveNoFrames() {
    #expect(frames([]).isEmpty)
  }

  @Test func twoHalvesLookLikeTall() {
    // With gaps and an odd area, so the rounding has to agree too.
    let odd = CGRect(x: 55, y: 38, width: 1745, height: 1131)
    let gaps = LayoutGaps(inner: 8, outer: 12)
    #expect(
      frames([half, half], in: odd, gaps: gaps)
        == TallLayout().frames(count: 2, in: odd, gaps: gaps))
  }

  @Test func aFullWindowLooksLikeFull() {
    let gaps = LayoutGaps(inner: 8, outer: 12)
    #expect(frames([full], gaps: gaps) == FullLayout().frames(count: 1, in: area, gaps: gaps))
  }

  @Test func twoQuartersShareAColumn() {
    #expect(
      frames([quarter, quarter, half]) == [
        CGRect(x: 0, y: 0, width: 500, height: 300),
        CGRect(x: 0, y: 300, width: 500, height: 300),
        CGRect(x: 500, y: 0, width: 500, height: 600),
      ])
  }

  @Test func aQuarterOnItsOwnFillsItsColumn() {
    #expect(frames([quarter])[0] == CGRect(x: 0, y: 0, width: 500, height: 600))
  }

  @Test func columnsLeftOfTheViewLieOffItsLeftEdge() {
    let result = frames([half, half, half, half], firstVisible: 2)
    #expect(result.map(\.minX) == [-1000, -500, 0, 500])
  }

  @Test func columnsAfterTheViewStartOnTheNextPage() {
    // The full column doesn't fit beside the first one, so it waits a whole page away rather than
    // showing at the edge.
    let result = frames([half, full, half])
    #expect(result.map(\.minX) == [0, 1000, 2000])
    #expect(result.map(\.width) == [500, 1000, 500])
  }

  @Test func pagesIncludeTheInnerGap() {
    let result = frames(
      [half, half, half, half], in: CGRect(x: 0, y: 0, width: 1010, height: 600),
      gaps: LayoutGaps(inner: 10))
    #expect(result.map(\.minX) == [0, 510, 1020, 1530])
    #expect(result.map(\.width) == [500, 500, 500, 500])
  }

  @Test func anyWindowOfAColumnPicksIt() {
    #expect(frames([half, quarter, quarter, half], firstVisible: 2)[1].minX == 0)
  }

  @Test func missingSizesCountAsHalf() {
    let input = LayoutInput(count: 3, sizes: [full])
    #expect(input.windowSizes == [full, half, half])
    #expect(LayoutInput(count: 1, sizes: [full, full]).windowSizes == [full])
  }

  @Test func sizesCycle() {
    #expect(WindowSize.allCases.map(\.next) == [full, quarter, half])
  }
}

@Suite("Strip layout: window sizes")
struct WindowSizeTests {
  @Test func windowsStartHalf() {
    #expect(makeWorkspace(1).size(of: WindowID(1)) == half)
  }

  @Test func setSizeNeedsATiledWindowAndAChange() {
    var workspace = makeWorkspace(1)
    let changed = workspace.setSize(full, of: WindowID(1))
    let again = workspace.setSize(full, of: WindowID(1))
    let untiled = workspace.setSize(full, of: WindowID(9))
    #expect(changed)
    #expect(!again, "already full")
    #expect(!untiled, "not tiled here")
    #expect(workspace.size(of: WindowID(1)) == full)
  }

  @Test func aWindowThatLeavesForgetsItsSize() {
    var workspace = makeWorkspace(1, 2)
    workspace.setSize(full, of: WindowID(2))
    workspace.remove(WindowID(2))
    workspace.insert(WindowID(2))
    #expect(workspace.size(of: WindowID(2)) == half)
  }

  @Test func aWindowKeepsItsSizeOnAnotherWorkspace() {
    var row = WorkspaceRow()
    row[0].insert(WindowID(1))
    row[0].setSize(full, of: WindowID(1))
    row.move(WindowID(1), to: 2)
    #expect(row[2].size(of: WindowID(1)) == full)
    #expect(row[0].sizes.isEmpty)
  }

  @Test func aQuarterArrivesHalfAndLeavesItsMateHalf() {
    var row = WorkspaceRow()
    row[0] = makeWorkspace(1, 2)
    row[0].setSizeWithPartner(quarter, of: WindowID(1))
    row.move(WindowID(1), to: 2)
    #expect(row[2].size(of: WindowID(1)) == half)
    #expect(row[0].size(of: WindowID(2)) == half)
  }

  // MARK: - Pairing quarters

  private func sizes(_ workspace: Workspace) -> [WindowSize] {
    workspace.windows.map(workspace.size(of:))
  }

  @Test func aQuarterTakesTheNextWindowAlong() {
    var workspace = makeWorkspace(1, 2, 3)
    #expect(workspace.setSizeWithPartner(quarter, of: WindowID(1)) == .changed)
    #expect(sizes(workspace) == [quarter, quarter, half])
  }

  @Test func theLastWindowPairsWithThePreviousOne() {
    var workspace = makeWorkspace(1, 2, 3)
    workspace.setSizeWithPartner(quarter, of: WindowID(3))
    #expect(sizes(workspace) == [half, quarter, quarter])
  }

  @Test func aWindowBeforeAPairPairsWithThePreviousOne() {
    var workspace = makeWorkspace(1, 2, 3, 4)
    workspace.setSizeWithPartner(quarter, of: WindowID(3))
    #expect(workspace.setSizeWithPartner(quarter, of: WindowID(2)) == .changed)
    #expect(sizes(workspace) == [quarter, quarter, quarter, quarter])
    #expect(StripColumns(sizes: sizes(workspace)).columns == [[0, 1], [2, 3]])
  }

  @Test func aQuarterNeedsAFreeNeighbour() {
    var single = makeWorkspace(1)
    #expect(single.setSizeWithPartner(quarter, of: WindowID(1)) == .noPartner)
    var hemmed = makeWorkspace(1, 2, 3, 4, 5)
    hemmed.setSizeWithPartner(quarter, of: WindowID(1))
    hemmed.setSizeWithPartner(quarter, of: WindowID(4))
    #expect(hemmed.setSizeWithPartner(quarter, of: WindowID(3)) == .noPartner)
    #expect(sizes(hemmed) == [quarter, quarter, half, quarter, quarter])
  }

  @Test func leavingAPairPutsTheMateBackToHalf() {
    var workspace = makeWorkspace(1, 2, 3)
    workspace.setSizeWithPartner(quarter, of: WindowID(1))
    #expect(workspace.setSizeWithPartner(full, of: WindowID(2)) == .changed)
    #expect(sizes(workspace) == [half, full, half])
  }

  @Test func closingOneOfAPairPutsTheOtherBackToHalf() {
    var workspace = makeWorkspace(1, 2, 3)
    workspace.setSizeWithPartner(quarter, of: WindowID(1))
    workspace.remove(WindowID(2))
    #expect(sizes(workspace) == [half, half])
  }

  @Test func settingTheSameSizeChangesNothing() {
    var workspace = makeWorkspace(1, 2)
    #expect(workspace.setSizeWithPartner(half, of: WindowID(1)) == .unchanged)
    #expect(workspace.setSizeWithPartner(full, of: WindowID(9)) == .unchanged)
  }
}
