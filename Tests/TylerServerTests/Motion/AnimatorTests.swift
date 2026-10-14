import CoreGraphics
import Testing
import TylerCore
import TylerTestSupport

@testable import TylerServer

@Suite("Animator: part-way runs")
@MainActor
struct AnimatorTests {
  private let clock = TestClock()
  /// 100 ms in 10 ms frames.
  private var animator: Animator {
    Animator(duration: .milliseconds(100), frameInterval: .milliseconds(10), clock: clock)
  }
  private let track = Track(
    id: WindowID(1), start: CGPoint(x: 0, y: 0), end: CGPoint(x: 1000, y: 0))

  /// Runs the animation to the end, advancing the clock a frame at a time, and returns the x of
  /// every step and whether it completed.
  private func run(
    from start: Double, to end: Double, minimumDuration: Duration = .zero
  ) async -> (steps: [CGFloat], isDone: Bool) {
    var steps: [CGFloat] = []
    let animator = animator
    let track = track
    let task = Task { @MainActor in
      let record: (WindowID, CGPoint) -> Void = { _, origin in steps.append(origin.x) }
      return await animator.run(
        [track], from: start, to: end, minimumDuration: minimumDuration, move: record)
    }
    await Task.yield()
    while !clock.hasSleepers { await Task.yield() }
    while clock.hasSleepers {
      clock.advance(by: .milliseconds(10))
      for _ in 0..<5 { await Task.yield() }
    }
    return (steps, await task.value)
  }

  @Test func eachFrameIsAnnouncedBeforeItsMoves() async {
    var events: [String] = []
    let animator = animator
    let track = track
    let task = Task { @MainActor in
      await animator.run(
        [track], frameStarted: { events.append("frame") }, move: { _, _ in events.append("move") })
    }
    await Task.yield()
    while !clock.hasSleepers { await Task.yield() }
    while clock.hasSleepers {
      clock.advance(by: .milliseconds(10))
      for _ in 0..<5 { await Task.yield() }
    }
    #expect(await task.value)
    #expect(events.count == 18, "100 ms in 10 ms frames: nine steps, then the caller places")
    #expect(events == Array(repeating: ["frame", "move"], count: 9).flatMap { $0 })
  }

  @Test func theRestOfAWayTakesItsShareOfTheDuration() async {
    let (steps, isDone) = await run(from: 0.6, to: 1)
    #expect(isDone)
    #expect(steps.count == 3, "40 ms in 10 ms frames: three steps, then the caller places")
    #expect(steps.allSatisfy { $0 > 600 && $0 < 1000 })
    #expect(steps == steps.sorted())
  }

  @Test func goingBackMovesTheOtherWay() async {
    let (steps, _) = await run(from: 0.5, to: 0)
    #expect(!steps.isEmpty)
    #expect(steps.allSatisfy { $0 < 500 && $0 > 0 })
    #expect(steps == steps.sorted(by: >))
  }

  @Test func itEasesOut() async {
    let (steps, _) = await run(from: 0, to: 1)
    let first = steps[1] - steps[0]
    let last = steps[steps.count - 1] - steps[steps.count - 2]
    #expect(first > last, "fast first, slow at the end")
  }

  @Test func aShortWayTakesAtLeastTheMinimum() async {
    let (quick, _) = await run(from: 0.9, to: 1)
    #expect(quick.isEmpty, "10 ms: done before the first frame")
    let (steps, isDone) = await run(from: 0.9, to: 1, minimumDuration: .milliseconds(60))
    #expect(isDone)
    #expect(steps.count == 5)
  }

  @Test func nothingLeftToGoFinishesAtOnce() async {
    let isDone = await animator.run([track], from: 1, to: 1) { _, _ in
      Issue.record("nothing should move")
    }
    #expect(isDone)
  }
}
