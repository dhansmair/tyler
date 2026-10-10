import CoreGraphics
import Testing

@testable import TylerCore

@Suite("WorkspaceStack")
struct WorkspaceStackTests {
  private func makeStack(_ assignments: [Int: [UInt32]], count: Int = 4) -> WorkspaceStack {
    var stack = WorkspaceStack(count: count)
    for (index, windows) in assignments {
      stack[index].sync(eligible: windows.map(WindowID.init))
    }
    return stack
  }

  @Test func startsOnTheFirstOfFourEmptyWorkspaces() {
    let stack = WorkspaceStack()
    #expect(stack.count == 4)
    #expect(stack.currentIndex == 0)
    #expect(stack.allWindows.isEmpty)
  }

  @Test func alwaysHasAtLeastOneWorkspace() {
    #expect(WorkspaceStack(count: 0).count == 1)
    #expect(WorkspaceStack(count: -3).count == 1)
  }

  @Test(arguments: [
    (0, WorkspaceTarget.next, 1), (3, .next, 0), (2, .prev, 1), (0, .prev, 3),
    (1, .number(1), 0), (1, .number(4), 3),
  ])
  func resolvesTargetsAndWraps(current: Int, target: WorkspaceTarget, expected: Int) {
    var stack = WorkspaceStack()
    stack.select(current)
    #expect(stack.index(of: target) == expected)
  }

  @Test func setGapsChangesEveryWorkspaceButKeepsLayoutAndRatio() {
    var stack = WorkspaceStack()
    stack[2].layout = .full
    stack[2].adjustRatio(by: 0.1)
    stack.setGaps(inner: 8, outer: 12)
    for index in stack.indices {
      #expect(stack[index].parameters.innerGap == 8)
      #expect(stack[index].parameters.outerGap == 12)
    }
    #expect(stack[2].layout == .full)
    #expect(stack[2].parameters.mainRatio == 0.6)
    #expect(stack[0].parameters.mainRatio == 0.5)
  }

  @Test(arguments: [0, 5, -1])
  func numbersOutOfRangeResolveToNothing(number: Int) {
    #expect(WorkspaceStack().index(of: .number(number)) == nil)
  }

  @Test func selectRejectsAnIndexOutOfRange() {
    var stack = WorkspaceStack()
    let outOfRange = stack.select(4)
    #expect(!outOfRange)
    #expect(stack.currentIndex == 0)
    let inRange = stack.select(2)
    #expect(inRange)
    #expect(stack.currentIndex == 2)
  }

  @Test func findsTheWorkspaceOfAWindow() {
    let stack = makeStack([0: [1, 2], 2: [3]])
    #expect(stack.index(containing: WindowID(2)) == 0)
    #expect(stack.index(containing: WindowID(3)) == 2)
    #expect(stack.index(containing: WindowID(9)) == nil)
    #expect(stack.allWindows == [WindowID(1), WindowID(2), WindowID(3)])
  }

  @Test func currentIsTheSelectedWorkspace() {
    var stack = makeStack([1: [5]])
    stack.select(1)
    #expect(stack.current.windows == [WindowID(5)])
    stack.current.insert(WindowID(6))
    #expect(stack[1].windows == [WindowID(5), WindowID(6)])
  }

  @Test func movingAWindowInsertsItAfterTheTargetsFocusAndFocusesIt() {
    var stack = makeStack([0: [1, 2], 1: [3, 4]])
    stack.setFocus(WindowID(3))
    let moved = stack.move(WindowID(1), to: 1)
    #expect(moved)
    #expect(stack[0].windows == [WindowID(2)])
    #expect(stack[1].windows == [WindowID(3), WindowID(1), WindowID(4)])
    #expect(stack[1].focused == WindowID(1))
  }

  @Test func movingToAnEmptyWorkspaceWorks() {
    var stack = makeStack([0: [1]])
    let moved = stack.move(WindowID(1), to: 3)
    #expect(moved)
    #expect(stack[3].windows == [WindowID(1)])
    #expect(stack[0].count == 0)
  }

  @Test func movingIsRefusedForUnknownWindowsTheSameWorkspaceAndBadIndices() {
    var stack = makeStack([0: [1]])
    let unknown = stack.move(WindowID(9), to: 1)
    #expect(!unknown)
    let sameWorkspace = stack.move(WindowID(1), to: 0)
    #expect(!sameWorkspace)
    let badIndex = stack.move(WindowID(1), to: 4)
    #expect(!badIndex)
    #expect(stack[0].windows == [WindowID(1)])
  }

  @Test func setFocusActsOnTheWindowsOwnWorkspace() {
    var stack = makeStack([0: [1], 2: [7, 8]])
    let known = stack.setFocus(WindowID(8))
    #expect(known)
    #expect(stack[2].focused == WindowID(8))
    #expect(stack[0].focused == nil)
    let unknown = stack.setFocus(WindowID(99))
    #expect(!unknown)
  }
}

@Suite("Parking and animation geometry")
struct ParkingTests {
  /// A display with the Dock on the left, as on the machine the limits were measured on.
  private let display = DisplayInfo(
    id: 1,
    frame: CGRect(x: 0, y: 0, width: 1800, height: 1169),
    visibleFrame: CGRect(x: 55, y: 38, width: 1745, height: 1131))

  @Test func parkedWindowsShowOnePointAtTheRightEdgeAtTheirOwnHeight() {
    let frame = Parking.frame(for: CGRect(x: 67, y: 51, width: 800, height: 600), on: display)
    #expect(frame == CGRect(x: 1799, y: 51, width: 800, height: 600))
    #expect(frame.intersection(display.visibleFrame).width == 1)
  }

  @Test func parkingUsesTheDisplaysOwnEdge() {
    let right = DisplayInfo(
      id: 2,
      frame: CGRect(x: 1800, y: -200, width: 1920, height: 1080),
      visibleFrame: CGRect(x: 1800, y: -200, width: 1920, height: 1080))
    let frame = Parking.frame(for: CGRect(x: 1900, y: 0, width: 10, height: 10), on: right)
    #expect(frame.origin == CGPoint(x: 3719, y: 0))
  }

  @Test func theAllowedPositionsKeepAPointInsideTheVisibleFrame() {
    // Measured: with the Dock on the left (visible frame from x = 55), x = -800 is accepted for
    // an 856-point window and x = -801 is pulled back; at the right edge 1799 is the limit.
    #expect(Parking.allowedX(width: 856, on: display) == -800...1799)
  }

  @Test(arguments: [(0.0, 0.0), (0.5, 0.5), (1.0, 1.0), (-1.0, 0.0), (2.0, 1.0)])
  func easingKeepsItsEndpointsAndClamps(progress: Double, expected: Double) {
    #expect(Easing.easeInOut(progress) == expected)
  }

  @Test func easingIsSlowAtTheEndsAndMonotonic() {
    #expect(Easing.easeInOut(0.1) < 0.1)
    #expect(Easing.easeInOut(0.9) > 0.9)
    let samples = stride(from: 0.0, through: 1.0, by: 0.05).map(Easing.easeInOut)
    #expect(zip(samples, samples.dropFirst()).allSatisfy { $0 <= $1 })
  }

  @Test func tracksInterpolateAndRoundToWholePoints() {
    let track = Track(id: WindowID(1), start: CGPoint(x: 0, y: 0), end: CGPoint(x: -1001, y: 0))
    #expect(track.position(at: 0) == .zero)
    #expect(track.position(at: 1) == CGPoint(x: -1001, y: 0))
    #expect(track.position(at: 0.5) == CGPoint(x: -501, y: 0), "-500.5 rounds away from zero")
  }

  @Test func tracksStopAtTheEdgeOfTheAllowedRange() {
    let track = Track(
      id: WindowID(1), start: CGPoint(x: 0, y: 5), end: CGPoint(x: 1000, y: 5),
      allowedX: 0...300)
    #expect(track.position(at: 0.5) == CGPoint(x: 300, y: 5))
    #expect(track.position(at: 1) == CGPoint(x: 300, y: 5))
    #expect(track.position(at: 0.1).x == 4, "before the edge it moves as if unclamped")
  }

  @Test func leavingWindowsMoveByTheVisibleWidthAndStopAtTheEdge() {
    let frame = CGRect(x: 932, y: 51, width: 856, height: 549)
    let left = Track.leaving(WindowID(1), from: frame, direction: .next, on: display)
    #expect(left.end == CGPoint(x: 932 - 1745, y: 51))
    #expect(left.position(at: 1) == CGPoint(x: -800, y: 51))
    let right = Track.leaving(WindowID(1), from: frame, direction: .prev, on: display)
    #expect(right.position(at: 1) == CGPoint(x: 1799, y: 51))
  }

  @Test func enteringWindowsStartAtTheEdgeOnTheOtherSide() {
    let slot = CGRect(x: 67, y: 51, width: 856, height: 1106)
    let fromRight = Track.entering(WindowID(1), into: slot, direction: .next, on: display)
    #expect(fromRight.position(at: 0) == CGPoint(x: 1799, y: 51))
    #expect(fromRight.position(at: 1) == slot.origin)
    let fromLeft = Track.entering(WindowID(1), into: slot, direction: .prev, on: display)
    #expect(fromLeft.position(at: 0) == CGPoint(x: -800, y: 51))
  }

  @Test func outgoingWindowsLeaveLeftwardsWhenScrollingDown() {
    #expect(ScrollDirection.next.outgoingOffset(width: 1000) == -1000)
    #expect(ScrollDirection.prev.outgoingOffset(width: 1000) == 1000)
    #expect(ScrollDirection.next.opposite == .prev)
    #expect(ScrollDirection.prev.opposite == .next)
  }
}
