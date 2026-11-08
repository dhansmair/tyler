import CoreGraphics
import Testing

@testable import TylerCore

/// A floating member takes no slot, keeps its place in the list and parks with its workspace.
@Suite("Workspace: floating members")
struct WorkspaceFloatingTests {
  private let display = DisplayInfo(
    id: 1, key: DisplayKey("display"), frame: CGRect(x: 0, y: 0, width: 1000, height: 600),
    visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 600))

  private func floating(_ floated: UInt32, in workspace: Workspace) -> Workspace {
    var workspace = workspace
    workspace.float(WindowID(floated))
    return workspace
  }

  @Test func aFloatingWindowTakesNoSlotButStaysAMember() {
    let workspace = floating(2, in: makeWorkspace(1, 2, 3))
    #expect(workspace.windows == ids(1, 3))
    #expect(workspace.members == ids(1, 2, 3))
    #expect(workspace.floating == [WindowID(2)])
    #expect(workspace.holds(WindowID(2)))
    #expect(!workspace.tiles(WindowID(2)))
  }

  @Test func onlyATiledWindowCanFloat() {
    var workspace = floating(2, in: makeWorkspace(1, 2))
    let again = workspace.float(WindowID(2))
    let unknown = workspace.float(WindowID(9))
    let tiled = workspace.tile(WindowID(1))
    #expect(!again && !unknown && !tiled)
  }

  @Test func theMainWindowTiledAgainIsTheMainWindow() {
    var workspace = floating(1, in: makeWorkspace(1, 2, 3))
    workspace.tile(WindowID(1))
    #expect(workspace.windows == ids(1, 2, 3))
  }

  @Test func aWindowTiledAgainKeepsItsPlaceWhenAnEarlierOneCloses() {
    var workspace = floating(3, in: makeWorkspace(1, 2, 3, 4))
    workspace.remove(WindowID(1))
    workspace.tile(WindowID(3))
    #expect(workspace.windows == ids(2, 3, 4))
  }

  @Test func floatingTheFocusedWindowMovesTheFocusOn() {
    let workspace = floating(2, in: makeWorkspace(1, 2, 3, focus: 2))
    #expect(workspace.focused == WindowID(3))
  }

  @Test func focusAndSwapSkipAFloatingWindow() {
    var workspace = floating(2, in: makeWorkspace(1, 2, 3, focus: 1))
    #expect(workspace.focus(.next) == WindowID(3))
    workspace.swap(.prev)
    #expect(workspace.windows == ids(3, 1))
    #expect(workspace.members == ids(3, 2, 1))
  }

  @Test func aFloatingWindowWhoseAppHidesFloatsAgainWhenShown() {
    var workspace = floating(2, in: makeWorkspace(1, 2, 3))
    let hid = workspace.hide(WindowID(2))
    #expect(hid)
    #expect(workspace.hidden == [WindowID(2)])
    #expect(workspace.shownFloating.isEmpty)
    workspace.show(WindowID(2))
    #expect(workspace.shownFloating == [WindowID(2)])
    #expect(workspace.windows == ids(1, 3))
  }

  @Test func itRemembersWhereOnlyItsFloatingMembersWere() {
    var workspace = floating(2, in: makeWorkspace(1, 2, 3))
    let frame = CGRect(x: 100, y: 100, width: 300, height: 200)
    workspace.rememberFloatingFrames([
      Placement(id: WindowID(1), frame: frame), Placement(id: WindowID(2), frame: frame),
    ])
    #expect(workspace.floatingFrame(of: WindowID(2)) == frame)
    #expect(workspace.floatingFrame(of: WindowID(1)) == nil)
  }

  @Test(arguments: [true, false])
  func tilingOrRemovingAWindowForgetsWhereItFloated(tiles: Bool) {
    var workspace = floating(2, in: makeWorkspace(1, 2, 3))
    workspace.rememberFloatingFrames([Placement(id: WindowID(2), frame: .zero)])
    if tiles {
      workspace.tile(WindowID(2))
      workspace.float(WindowID(2))
    } else {
      workspace.remove(WindowID(2))
    }
    #expect(workspace.floatingFrame(of: WindowID(2)) == nil)
  }

  @Test func syncKeepsAFloatingMemberAndDropsOneThatIsGone() {
    var workspace = floating(2, in: makeWorkspace(1, 2, 3))
    let kept = workspace.sync(eligible: ids(1, 2, 3))
    #expect(!kept)
    #expect(workspace.floating == [WindowID(2)])
    let dropped = workspace.sync(eligible: ids(1, 3))
    #expect(dropped)
    #expect(workspace.members == ids(1, 3))
  }

  @Test func syncHidesAFloatingMemberAndKeepsItFloating() {
    var workspace = floating(2, in: makeWorkspace(1, 2, 3))
    workspace.sync(eligible: ids(1, 3), hiding: [WindowID(2)])
    #expect(workspace.flags(of: WindowID(2)) == [.hidden, .floating])
    workspace.sync(eligible: ids(1, 2, 3))
    #expect(workspace.flags(of: WindowID(2)) == .floating)
  }

  @Test func aWindowJoiningFloatingGoesLast() {
    var workspace = makeWorkspace(1, 2, 3, focus: 1)
    workspace.sync(eligible: ids(1, 2, 3, 8, 9), floating: [WindowID(8)])
    #expect(workspace.members == ids(1, 9, 2, 3, 8))
    #expect(workspace.floating == [WindowID(8)])
  }

  @Test(arguments: LayoutKind.allCases)
  func aFloatingMemberChangesNoFrame(layout: LayoutKind) {
    let area = CGRect(x: 0, y: 0, width: 1200, height: 800)
    var withFloating = floating(2, in: makeWorkspace(1, 2, 3))
    withFloating.layout = layout
    var without = makeWorkspace(1, 3)
    without.layout = layout
    #expect(
      withFloating.arrangement(in: area, gaps: LayoutGaps())
        == without.arrangement(in: area, gaps: LayoutGaps()))
  }

  /// In the strip, floating the window at the left of the view moves the view on, as hiding it
  /// does.
  @Test(arguments: [LayoutKind.tall, .grid, .full])
  func floatingAndTilingAgainRestoresEveryFrame(layout: LayoutKind) {
    let area = CGRect(x: 0, y: 0, width: 1200, height: 800)
    var workspace = makeWorkspace(1, 2, 3, 4, focus: 2)
    workspace.layout = layout
    workspace.promote()
    let before = workspace.arrangement(in: area, gaps: LayoutGaps())
    workspace.float(WindowID(1))
    workspace.tile(WindowID(1))
    #expect(workspace.arrangement(in: area, gaps: LayoutGaps()) == before)
  }

  @Test func aFloatingWindowComesBackWhereItWas() {
    var workspace = floating(2, in: makeWorkspace(1, 2, 3))
    let frame = CGRect(x: 100, y: 100, width: 300, height: 200)
    workspace.rememberFloatingFrames([Placement(id: WindowID(2), frame: frame)])
    let placements = workspace.floatingPlacements(on: display) { _ in nil }
    #expect(placements == [Placement(id: WindowID(2), frame: frame)])
  }

  @Test func aFloatingWindowWithoutAFrameComesBackPulledOntoTheDisplay() {
    let workspace = floating(2, in: makeWorkspace(1, 2, 3))
    let parked = CGRect(x: 999, y: 100, width: 300, height: 200)
    let placements = workspace.floatingPlacements(on: display) { _ in parked }
    #expect(placements.map(\.frame) == [CGRect(x: 700, y: 100, width: 300, height: 200)])
  }

  @Test func aHiddenFloatingWindowDoesNotComeBack() {
    var workspace = floating(2, in: makeWorkspace(1, 2, 3))
    workspace.hide(WindowID(2))
    #expect(workspace.floatingPlacements(on: display) { _ in .zero }.isEmpty)
  }

  @Test func aRemovedWorkspaceHandsOverItsFloatingMembersAndWhereTheyWere() {
    var row = WorkspaceRow(count: 2)
    row[1] = floating(2, in: makeWorkspace(1, 2))
    let frame = CGRect(x: 100, y: 100, width: 300, height: 200)
    row[1].rememberFloatingFrames([Placement(id: WindowID(2), frame: frame)])
    row.setNumbers([1])
    #expect(row[0].members == ids(1, 2))
    #expect(row[0].floating == [WindowID(2)])
    #expect(row[0].floatingFrame(of: WindowID(2)) == frame)
  }
}
