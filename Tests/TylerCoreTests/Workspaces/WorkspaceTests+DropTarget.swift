import CoreGraphics
import Testing

@testable import TylerCore

/// The parts of `Workspace` that swap by drag and drop builds on.
@Suite("Workspace: drop targets")
struct WorkspaceDropTargetTests {
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

  @Test(arguments: [
    (UInt32(3), CGPoint(x: 100, y: 100), UInt32?(1)),
    (3, CGPoint(x: 700, y: 100), 2),
    (1, CGPoint(x: 700, y: 500), 3),
    (3, CGPoint(x: 700, y: 500), nil),  // its own slot
    (3, CGPoint(x: 500, y: 100), nil),  // the gap between the columns
    (3, CGPoint(x: 700, y: 300), nil),  // the gap between the stacked windows
    (3, CGPoint(x: 1200, y: 100), nil),  // outside the area
    (9, CGPoint(x: 100, y: 100), nil),  // not tiled here
  ])
  func theDropTargetIsTheSlotUnderThePoint(dragged: UInt32, point: CGPoint, target: UInt32?) {
    let workspace = makeGappedWorkspace()
    #expect(
      workspace.dropTarget(
        for: WindowID(dragged), at: point, on: Self.dropDisplay, gaps: LayoutGaps(inner: 20))
        == target.map(WindowID.init))
  }

  @Test func inFullNothingIsADropTarget() {
    var workspace = makeWorkspace(1, 2)
    workspace.layout = .full
    #expect(
      workspace.dropTarget(
        for: WindowID(2), at: CGPoint(x: 100, y: 100), on: Self.dropDisplay, gaps: LayoutGaps())
        == nil)
  }

  @Test func aSingleWindowHasNoDropTarget() {
    let workspace = makeWorkspace(1)
    #expect(
      workspace.dropTarget(
        for: WindowID(1), at: CGPoint(x: 100, y: 100), on: Self.dropDisplay, gaps: LayoutGaps())
        == nil)
  }

  // MARK: - Arrivals from another display

  /// Window 9 arrives at windows 1 and 2 in `tall`, in 1000 × 600 with a 20-point inner gap: the
  /// slot it would take is the left half as the master, the upper right after window 1, or the
  /// lower right last.
  @Test(arguments: [
    (CGPoint(x: 100, y: 100), Int?(0)),
    (CGPoint(x: 700, y: 100), 1),
    (CGPoint(x: 700, y: 500), 2),
    (CGPoint(x: 500, y: 100), nil),  // the gap between the columns
    (CGPoint(x: 1200, y: 100), nil),  // outside the area
  ])
  func anArrivalGoesInWhereItsSlotIsUnderThePoint(point: CGPoint, index: Int?) {
    let workspace = makeWorkspace(1, 2)
    #expect(
      workspace.arrivalIndex(
        of: WindowID(9), at: point, on: Self.dropDisplay, gaps: LayoutGaps(inner: 20)) == index)
  }

  @Test(arguments: [(CGPoint(x: 100, y: 100), 0), (CGPoint(x: 700, y: 500), 1)])
  func anArrivalBesideASingleWindowTakesTheHalfUnderThePoint(point: CGPoint, index: Int) {
    #expect(
      makeWorkspace(1).arrivalIndex(
        of: WindowID(9), at: point, on: Self.dropDisplay, gaps: LayoutGaps())
        == index)
  }

  @Test func anArrivalOnAnEmptyWorkspaceGoesFirst() {
    #expect(
      Workspace().arrivalIndex(
        of: WindowID(9), at: CGPoint(x: 700, y: 500), on: Self.dropDisplay, gaps: LayoutGaps()) == 0
    )
  }

  @Test(arguments: [(0, ids(9, 1, 2)), (1, ids(1, 9, 2)), (2, ids(1, 2, 9)), (7, ids(1, 2, 9))])
  func arrivingPutsTheWindowInAtTheIndex(index: Int, windows: [WindowID]) {
    let workspace = makeWorkspace(1, 2)
    #expect(workspace.arriving(WindowID(9), at: index).windows == windows)
    #expect(workspace.windows == ids(1, 2), "the workspace itself stays as it was")
  }
}
