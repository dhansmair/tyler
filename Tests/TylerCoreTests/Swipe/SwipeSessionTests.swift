import CoreGraphics
import Testing

@testable import TylerCore

/// A 1000 × 600 display with no neighbour. Swiping the row: window 1 is on screen, window 2 on
/// the previous workspace (0), window 3 on the next (2). Swiping a view: four half windows in a
/// strip, which rests at windows 1, 2 and 3.
@Suite("SwipeSession")
struct SwipeSessionTests {
  private static let area = CGRect(x: 0, y: 0, width: 1000, height: 600)
  private let display = DisplayInfo(id: 1, frame: Self.area, visibleFrame: Self.area)
  /// A whole display width per trackpad width, so travel and offset are the same number.
  private let distance = 1.0

  private func plan(to target: Int, _ direction: ScrollDirection, entering: UInt32) -> SlidePlan {
    SlidePlan(
      to: target, direction: direction,
      leaving: [Placement(id: WindowID(1), frame: Self.area)],
      entering: [Placement(id: WindowID(entering), frame: Self.area)], on: display)
  }

  private var prev: SlidePlan { plan(to: 0, .prev, entering: 2) }
  private var next: SlidePlan { plan(to: 2, .next, entering: 3) }
  private var row: SwipeSession { SwipeSession(target: .workspaceRow(prev: prev, next: next)) }

  private var view: SwipeSession {
    var workspace = Workspace(layout: .strip)
    for value in UInt32(1)...4 { workspace.append(WindowID(value)) }
    let scroll = ViewScroll(
      views: workspace.views(in: Self.area, gaps: LayoutGaps()), current: WindowID(1),
      on: display)
    return SwipeSession(target: .view(scroll!))
  }

  @Test func theRowFollowsTheFingersOnceTheirSideIsOut() {
    var session = row
    session.move(travel: -0.25, distance: distance)
    let first = session.step()
    #expect(first.placements == next.start, "the next workspace's windows come out")
    #expect(first.nudges.map(\.id) == next.tracks.map(\.id))
    #expect(
      first.nudges.first?.origin == next.tracks.first?.position(at: 0.25, easing: Easing.linear))
    session.move(travel: -0.5, distance: distance)
    let step = session.step()
    #expect(step.placements.isEmpty, "out already")
  }

  @Test func turningBackPutsTheOtherSideAway() {
    var session = row
    session.move(travel: -0.25, distance: distance)
    _ = session.step()
    session.move(travel: 0.25, distance: distance)
    let step = session.step()
    #expect(step.placements == next.returns + prev.start)
  }

  @Test func theRowGoesNoFurtherThanTheNeighbour() {
    var session = row
    session.move(travel: -3, distance: 0.3)
    #expect(session.offset == -1)
  }

  @Test(arguments: [
    (-0.6, 0.0, SwipeEnding.Destination.workspace(index: 2)),
    (-0.2, 0.0, .stay),
    (-0.2, -1.5, .workspace(index: 2)),
    (0.6, 0.0, .workspace(index: 0)),
  ])
  func theRowSettlesWhereSnapSays(
    travel: Double, velocity: Double, destination: SwipeEnding.Destination
  ) throws {
    var session = row
    session.move(travel: travel, distance: distance)
    _ = session.step()
    let ended = session.end(velocity: velocity, distance: distance)
    let ending = try #require(ended)
    #expect(ending.destination == destination)
    let settle = try #require(ending.settle)
    #expect(settle.start == abs(travel))
    #expect(settle.end == (destination == .stay ? 0 : 1))
    #expect(settle.isReturn == (destination == .stay))
  }

  @Test func aFlickBringsOutASideTheFingersHadntShown() throws {
    var session = row
    let ended = session.end(velocity: 2, distance: distance)
    let ending = try #require(ended)
    #expect(ending.placements == prev.start)
    #expect(ending.destination == .workspace(index: 0))
    #expect(ending.settle?.start == 0)
  }

  @Test func aSwipeThatWentNowhereEndsWithNothingToDo() throws {
    var session = row
    let ended = session.end(velocity: 0, distance: distance)
    let ending = try #require(ended)
    #expect(ending == SwipeEnding())
    var still = view
    let stillEnded = still.end(velocity: 0, distance: distance)
    #expect(stillEnded == nil)
  }

  @Test func abandoningPutsTheShownSideBack() {
    var session = row
    #expect(session.abandon().isEmpty)
    session.move(travel: -0.25, distance: distance)
    _ = session.step()
    #expect(session.abandon() == next.returns)
  }

  @Test func theViewMovesNothingUntilItLeavesItsFirstView() {
    var session = view
    session.move(travel: 0.2, distance: distance)
    let step = session.step()
    #expect(step == SwipeStep(), "the strip's start: nothing before it")
  }

  @Test func theViewSettlesOnTheNextViewItWasPulledTowards() throws {
    var session = view
    session.move(travel: -0.3, distance: distance)
    let first = session.step()
    #expect(!first.placements.isEmpty, "the windows of the scroll come out")
    session.move(travel: -0.35, distance: distance)
    let step = session.step()
    #expect(step.placements.isEmpty)
    let ended = session.end(velocity: 0, distance: distance)
    let ending = try #require(ended)
    #expect(ending.destination == .view(firstVisible: WindowID(2)))
    #expect(ending.settle?.end == 1)
    #expect(ending.settle?.isReturn == false)
    #expect(!session.abandon().isEmpty, "what came out goes back")
  }
}
