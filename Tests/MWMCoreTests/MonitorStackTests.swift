import CoreGraphics
import Testing

@testable import MWMCore

@Suite("MonitorStack")
struct MonitorStackTests {
  private func makeStack(_ assignments: [Int: [UInt32]], count: Int = 4) -> MonitorStack {
    var stack = MonitorStack(count: count)
    for (index, windows) in assignments {
      stack[index].sync(eligible: windows.map(WindowID.init))
    }
    return stack
  }

  @Test func startsOnTheFirstOfFourEmptyMonitors() {
    let stack = MonitorStack()
    #expect(stack.count == 4)
    #expect(stack.currentIndex == 0)
    #expect(stack.allWindows.isEmpty)
  }

  @Test func alwaysHasAtLeastOneMonitor() {
    #expect(MonitorStack(count: 0).count == 1)
    #expect(MonitorStack(count: -3).count == 1)
  }

  @Test(arguments: [
    (0, MonitorTarget.down, 1), (3, .down, 0), (2, .up, 1), (0, .up, 3),
    (1, .number(1), 0), (1, .number(4), 3),
  ])
  func resolvesTargetsAndWraps(current: Int, target: MonitorTarget, expected: Int) {
    var stack = MonitorStack()
    stack.select(current)
    #expect(stack.index(of: target) == expected)
  }

  @Test(arguments: [0, 5, -1])
  func numbersOutOfRangeResolveToNothing(number: Int) {
    #expect(MonitorStack().index(of: .number(number)) == nil)
  }

  @Test func selectRejectsAnIndexOutOfRange() {
    var stack = MonitorStack()
    let outOfRange = stack.select(4)
    #expect(!outOfRange)
    #expect(stack.currentIndex == 0)
    let inRange = stack.select(2)
    #expect(inRange)
    #expect(stack.currentIndex == 2)
  }

  @Test func findsTheMonitorOfAWindow() {
    let stack = makeStack([0: [1, 2], 2: [3]])
    #expect(stack.monitor(of: WindowID(2)) == 0)
    #expect(stack.monitor(of: WindowID(3)) == 2)
    #expect(stack.monitor(of: WindowID(9)) == nil)
    #expect(stack.allWindows == [WindowID(1), WindowID(2), WindowID(3)])
  }

  @Test func currentIsTheSelectedMonitor() {
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

  @Test func movingToAnEmptyMonitorWorks() {
    var stack = makeStack([0: [1]])
    let moved = stack.move(WindowID(1), to: 3)
    #expect(moved)
    #expect(stack[3].windows == [WindowID(1)])
    #expect(stack[0].count == 0)
  }

  @Test func movingIsRefusedForUnknownWindowsTheSameMonitorAndBadIndices() {
    var stack = makeStack([0: [1]])
    let unknown = stack.move(WindowID(9), to: 1)
    #expect(!unknown)
    let sameMonitor = stack.move(WindowID(1), to: 0)
    #expect(!sameMonitor)
    let badIndex = stack.move(WindowID(1), to: 4)
    #expect(!badIndex)
    #expect(stack[0].windows == [WindowID(1)])
  }

  @Test func setFocusActsOnTheWindowsOwnMonitor() {
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
  private let display = DisplayInfo(
    id: 1,
    frame: CGRect(x: 0, y: 0, width: 1800, height: 1169),
    visibleFrame: CGRect(x: 0, y: 38, width: 1800, height: 1131))

  @Test func parkedWindowsShowOnePointInTheBottomRightCorner() {
    let frame = Parking.frame(for: CGSize(width: 800, height: 600), on: display)
    #expect(frame == CGRect(x: 1799, y: 1168, width: 800, height: 600))
    #expect(frame.intersection(display.frame).size == CGSize(width: 1, height: 1))
  }

  @Test func parkingUsesTheDisplaysOwnCorner() {
    let right = DisplayInfo(
      id: 2,
      frame: CGRect(x: 1800, y: -200, width: 1920, height: 1080),
      visibleFrame: CGRect(x: 1800, y: -200, width: 1920, height: 1080))
    let frame = Parking.frame(for: CGSize(width: 10, height: 10), on: right)
    #expect(frame.origin == CGPoint(x: 3719, y: 879))
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
    let track = Track(id: WindowID(1), start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: -1001))
    #expect(track.position(at: 0) == .zero)
    #expect(track.position(at: 1) == CGPoint(x: 0, y: -1001))
    #expect(track.position(at: 0.5) == CGPoint(x: 0, y: -501), "-500.5 rounds away from zero")
  }

  @Test func outgoingWindowsLeaveUpwardsWhenScrollingDown() {
    #expect(ScrollDirection.down.outgoingOffset(height: 1000) == -1000)
    #expect(ScrollDirection.up.outgoingOffset(height: 1000) == 1000)
  }
}
