import CoreGraphics
import Testing

@testable import TylerCore

/// Four half windows in 1000 × 600, scrolling from windows 1 and 2 to windows 2 and 3.
@Suite("Strip layout: scroll plan")
struct ScrollPlanTests {
  private static let area = CGRect(x: 0, y: 0, width: 1000, height: 600)
  private let display = DisplayInfo(id: 1, frame: Self.area, visibleFrame: Self.area)

  private func frame(left: CGFloat) -> CGRect {
    CGRect(x: left, y: 0, width: 500, height: 600)
  }

  private var plan: ScrollPlan {
    var workspace = Workspace(layout: .strip)
    for value: UInt32 in [1, 2, 3, 4] { workspace.append(WindowID(value)) }
    workspace.setFocus(WindowID(1))
    let before = workspace.arrangement(in: Self.area, gaps: LayoutGaps())
    workspace.setFocus(WindowID(3))
    let after = workspace.arrangement(in: Self.area, gaps: LayoutGaps())
    return ScrollPlan(from: before, to: after, on: display)
  }

  @Test func windowsOutOfViewAtBothEndsStayParked() {
    #expect(plan.windows == Set(ids(1, 2, 3)))
  }

  @Test func theIncomingWindowStartsWhereItIsParked() {
    #expect(plan.start == [Placement(id: WindowID(3), frame: frame(left: 999))])
  }

  @Test func theLeavingWindowParksAndTheOthersEndInTheirSlots() {
    #expect(plan.finals.map(\.frame) == [frame(left: 999), frame(left: 0), frame(left: 500)])
  }

  @Test func callingItOffPutsTheViewBack() {
    #expect(plan.returns.map(\.frame) == [frame(left: 0), frame(left: 500), frame(left: 999)])
  }

  @Test func theLeavingWindowStopsAtTheLeftEdge() {
    // Tracks keep x where macOS accepts it: at most all but one point off the left edge.
    #expect(plan.tracks[0].position(at: 1).x == -499)
  }

  @Test func halfwayEveryWindowHasMovedHalfAPage() {
    #expect(plan.placements(at: 0.5).map(\.frame.minX) == [-250, 250, 750])
  }
}
