import CoreGraphics
import Testing

@testable import TylerCore

/// The parts of `Workspace` that dragging a window and dropping it builds on.
@Suite("Workspace: dropping")
struct WorkspaceDropTests {
  // MARK: - Swapping by ID

  @Test func swappingTwoWindowsByIDKeepsFocusAndTheOthersInOrder() {
    var workspace = makeWorkspace(1, 2, 3, 4, focus: 2)
    let swapped = workspace.swap(WindowID(4), with: WindowID(1))
    #expect(swapped)
    #expect(workspace.windows == ids(4, 2, 3, 1))
    #expect(workspace.focused == WindowID(2))
  }

  @Test(arguments: [(UInt32(1), UInt32(1)), (1, 9), (9, 1)])
  func swappingByIDNeedsTwoDifferentTiledWindows(first: UInt32, second: UInt32) {
    var workspace = makeWorkspace(1, 2)
    let swapped = workspace.swap(WindowID(first), with: WindowID(second))
    #expect(!swapped)
    #expect(workspace.windows == ids(1, 2))
  }

  // MARK: - Drop targets

  /// In `tall` with 3 windows in 1000 × 600 and a 20-point inner gap, window 1 has the left half
  /// up to x = 490, windows 2 and 3 the right half from x = 510, split at y = 290…310.
  private static let dropArea = CGRect(x: 0, y: 0, width: 1000, height: 600)
  private static let dropDisplay = DisplayInfo(id: 1, frame: dropArea, visibleFrame: dropArea)

  private func makeGappedWorkspace() -> Workspace {
    var workspace = Workspace()
    for value: UInt32 in [1, 2, 3] { workspace.insert(WindowID(value)) }
    return workspace
  }

  /// Window 3 on the master's slot goes first, on window 2's goes second; window 1 on window 3's
  /// goes last. Over its own slot a window keeps its place.
  @Test(arguments: [
    (UInt32(3), CGPoint(x: 100, y: 100), Int?(0)),
    (3, CGPoint(x: 700, y: 100), 1),
    (1, CGPoint(x: 700, y: 500), 2),
    (3, CGPoint(x: 700, y: 500), 2),  // its own slot
    (3, CGPoint(x: 500, y: 100), nil),  // the gap between the columns
    (3, CGPoint(x: 700, y: 300), nil),  // the gap between the stacked windows
    (3, CGPoint(x: 1200, y: 100), nil),  // outside the area
    (9, CGPoint(x: 100, y: 100), nil),  // not tiled here
  ])
  func theDropPlaceIsTheSlotUnderThePoint(dragged: UInt32, point: CGPoint, index: Int?) {
    let workspace = makeGappedWorkspace()
    #expect(
      workspace.dropPlace(
        for: WindowID(dragged), at: point, on: Self.dropDisplay, gaps: LayoutGaps(inner: 20)
      )?.index == index)
  }

  @Test func inFullAWindowKeepsItsPlace() {
    var workspace = makeWorkspace(1, 2)
    workspace.layout = .full
    #expect(
      workspace.dropPlace(
        for: WindowID(2), at: CGPoint(x: 100, y: 100), on: Self.dropDisplay, gaps: LayoutGaps())
        == ListPlace(index: 1))
  }

  @Test(arguments: [(UInt32(1), 2, ids(2, 3, 1)), (3, 0, ids(3, 1, 2)), (2, 1, ids(1, 2, 3))])
  func movingShiftsTheWindowsInBetween(window: UInt32, index: Int, windows: [WindowID]) {
    var workspace = makeWorkspace(1, 2, 3, focus: 2)
    workspace.move(WindowID(window), to: ListPlace(index: index))
    #expect(workspace.windows == windows)
    #expect(workspace.focused == WindowID(2))
  }

  @Test(arguments: [(UInt32(9), 0), (1, 3)])
  func movingNeedsATiledWindowAndAPlaceInTheList(window: UInt32, index: Int) {
    var workspace = makeWorkspace(1, 2, 3)
    let moved = workspace.move(WindowID(window), to: ListPlace(index: index))
    #expect(!moved)
    #expect(workspace.windows == ids(1, 2, 3))
  }

  // MARK: - Tall's sections

  /// Windows 1 to `count` in `tall` with `mains` in the master section, in 1000 × 600 without
  /// gaps.
  private func sectioned(_ count: Int, mains: Int) -> Workspace {
    var workspace = Workspace()
    for id in windowIDs(count: count) { workspace.insert(id) }
    workspace.update(\.tall) { state, _ in state = TallLayoutState(mainCount: mains) }
    return workspace
  }

  private func dropPlace(
    of window: UInt32, at point: CGPoint, in workspace: Workspace
  ) -> ListPlace? {
    workspace.dropPlace(
      for: WindowID(window), at: point, on: Self.dropDisplay, gaps: LayoutGaps())
  }

  @Test func aStackedWindowOverTheMainColumnJoinsTheMainSection() {
    let workspace = sectioned(4, mains: 2)
    let place = dropPlace(of: 4, at: CGPoint(x: 100, y: 100), in: workspace)
    #expect(place == ListPlace(index: 0, isInMainSection: true))
    let moved = workspace.moving(WindowID(4), to: place!)
    #expect(moved.windows == ids(4, 1, 2, 3))
    #expect(moved.mainSectionCount == 3)
  }

  @Test func aMainOverTheStackJoinsTheStack() {
    let workspace = sectioned(4, mains: 2)
    let place = dropPlace(of: 1, at: CGPoint(x: 700, y: 500), in: workspace)
    #expect(place == ListPlace(index: 3, isInMainSection: false))
    let moved = workspace.moving(WindowID(1), to: place!)
    #expect(moved.windows == ids(2, 3, 4, 1))
    #expect(moved.mainSectionCount == 1)
  }

  @Test func aMainMovedWithinTheMainSectionKeepsItsSize() {
    let workspace = sectioned(4, mains: 2)
    let place = dropPlace(of: 2, at: CGPoint(x: 100, y: 100), in: workspace)
    #expect(place == ListPlace(index: 0, isInMainSection: true))
    let moved = workspace.moving(WindowID(2), to: place!)
    #expect(moved.windows == ids(2, 1, 3, 4))
    #expect(moved.mainSectionCount == 2)
  }

  /// Every window a master gives one column; the right half is where a new stack would go.
  @Test func fromOneColumnAWindowCanStartAStack() {
    let workspace = sectioned(2, mains: 2)
    let place = dropPlace(of: 2, at: CGPoint(x: 700, y: 100), in: workspace)
    #expect(place == ListPlace(index: 1, isInMainSection: false))
    #expect(workspace.moving(WindowID(2), to: place!).mainSectionCount == 1)
  }

  @Test func outsideTallTheMainSectionStaysAsItIs() {
    var workspace = sectioned(3, mains: 2)
    workspace.layout = .grid
    workspace.move(WindowID(3), to: ListPlace(index: 0, isInMainSection: true))
    #expect(workspace.windows == ids(3, 1, 2))
    #expect(workspace.layoutStates.tall.mainCount == 2)
  }

  // MARK: - Arrivals from another display

  private func arrivalIndex(
    at point: CGPoint, in workspace: Workspace, gaps: LayoutGaps = LayoutGaps()
  ) -> Int? {
    workspace.arrivalPlace(of: WindowID(9), at: point, on: Self.dropDisplay, gaps: gaps)?.index
  }

  /// Window 9 arrives at windows 1 and 2 in `tall`, in 1000 × 600 with a 20-point inner gap: the
  /// slot it would take is the upper right after window 1, the lower right last, or, over the
  /// left half, in the master section, above or below window 1.
  @Test(arguments: [
    (CGPoint(x: 100, y: 100), Int?(0)),
    (CGPoint(x: 100, y: 500), 1),
    (CGPoint(x: 700, y: 100), 1),
    (CGPoint(x: 700, y: 500), 2),
    (CGPoint(x: 500, y: 100), nil),  // the gap between the columns
    (CGPoint(x: 1200, y: 100), nil),  // outside the area
  ])
  func anArrivalGoesInWhereItsSlotIsUnderThePoint(point: CGPoint, index: Int?) {
    #expect(arrivalIndex(at: point, in: makeWorkspace(1, 2), gaps: LayoutGaps(inner: 20)) == index)
  }

  @Test func anArrivalOverTheMainColumnJoinsTheMainSection() throws {
    let workspace = makeWorkspace(1, 2)
    let place = try #require(
      workspace.arrivalPlace(
        of: WindowID(9), at: CGPoint(x: 100, y: 100), on: Self.dropDisplay, gaps: LayoutGaps()))
    #expect(place == ListPlace(index: 0, isInMainSection: true))
    let arrived = workspace.arriving(WindowID(9), at: place)
    #expect(arrived.windows == ids(9, 1, 2))
    #expect(arrived.mainSectionCount == 2)
  }

  @Test func anArrivalOverTheStackLeavesTheMainSection() {
    let arrived = makeWorkspace(1, 2).arriving(WindowID(9), at: ListPlace(index: 1))
    #expect(arrived.windows == ids(1, 9, 2))
    #expect(arrived.mainSectionCount == 1)
  }

  @Test(arguments: [(CGPoint(x: 100, y: 100), 0), (CGPoint(x: 700, y: 500), 1)])
  func anArrivalBesideASingleWindowTakesTheHalfUnderThePoint(point: CGPoint, index: Int) {
    var grid = makeWorkspace(1)
    grid.layout = .grid
    #expect(arrivalIndex(at: point, in: grid) == index)
    #expect(arrivalIndex(at: point, in: makeWorkspace(1)) == index)
  }

  @Test func anArrivalOnAnEmptyWorkspaceGoesFirst() {
    #expect(arrivalIndex(at: CGPoint(x: 700, y: 500), in: Workspace()) == 0)
  }

  @Test(arguments: [(0, ids(9, 1, 2)), (1, ids(1, 9, 2)), (2, ids(1, 2, 9)), (7, ids(1, 2, 9))])
  func arrivingPutsTheWindowInAtTheIndex(index: Int, windows: [WindowID]) {
    let workspace = makeWorkspace(1, 2)
    #expect(workspace.arriving(WindowID(9), at: ListPlace(index: index)).windows == windows)
    #expect(workspace.windows == ids(1, 2), "the workspace itself stays as it was")
  }
}
