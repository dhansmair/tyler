import CoreGraphics
import Foundation
import Testing

@testable import TylerCore

@Suite("SwipeRecognizer")
struct SwipeRecognizerTests {
  /// `count` fingers side by side around (`x`, `y`), 0.1 apart vertically.
  private func frame(
    _ time: TimeInterval, fingers count: Int, x across: Double, y along: Double = 0.5
  ) -> TouchFrame {
    TouchFrame(
      time: time,
      positions: (0..<count).map { CGPoint(x: across, y: along + Double($0) * 0.1) })
  }

  /// Feeds every frame and collects what came out.
  private func run(_ frames: [TouchFrame], fingers: Int = 3) -> [SwipeUpdate] {
    var recognizer = SwipeRecognizer(fingers: fingers)
    return frames.flatMap { recognizer.feed($0) }
  }

  @Test func aSidewaysSwipeBeginsMovesAndEndsWhenTheFingersLift() {
    let updates = run([
      frame(0.00, fingers: 1, x: 0.5),
      frame(0.01, fingers: 2, x: 0.5),
      frame(0.02, fingers: 3, x: 0.5),
      frame(0.03, fingers: 3, x: 0.46),
      frame(0.04, fingers: 3, x: 0.40),
      frame(0.05, fingers: 2, x: 0.40),
    ])
    #expect(updates.count == 3)
    #expect(updates[0] == .began)
    guard case .moved(let offset) = updates[1], case .ended(let velocity) = updates[2] else {
      Issue.record("unexpected updates \(updates)")
      return
    }
    // Counted from where the swipe began (0.46), smoothed: between nothing and the raw -0.06.
    #expect(offset < 0 && offset > -0.06)
    #expect(abs(velocity - -6) < 1e-6, "from the raw positions: 0.06 widths in 0.01 s")
  }

  @Test func theContentDoesntJumpWhenTheSwipeBegins() {
    let updates = run([
      frame(0, fingers: 3, x: 0.5), frame(0.01, fingers: 3, x: 0.45),
      frame(0.02, fingers: 3, x: 0.45),
    ])
    #expect(updates == [.began, .moved(offset: 0)])
  }

  @Test func movingRightGivesPositiveOffsets() {
    let updates = run([
      frame(0, fingers: 3, x: 0.2), frame(0.01, fingers: 3, x: 0.3),
      frame(0.02, fingers: 3, x: 0.4),
    ])
    #expect(updates.first == .began)
    guard case .moved(let offset) = updates.last else {
      Issue.record("expected a move, got \(updates)")
      return
    }
    #expect(offset > 0)
  }

  @Test func smallMovesDontBeginASwipe() {
    let updates = run([
      frame(0, fingers: 3, x: 0.5), frame(0.01, fingers: 3, x: 0.51),
      frame(0.02, fingers: 0, x: 0),
    ])
    #expect(updates.isEmpty)
  }

  @Test func slowJitteryFingersMoveTheContentLessThanTheyTwitch() {
    // Fingers creeping left at 0.05 widths per second with ±0.002 of sensor noise, 100 frames
    // a second. Raw, the offset steps back 0.0035 on every other frame (about 20 points with the
    // default swipe distance); smoothed, under a point.
    var frames = [frame(0, fingers: 3, x: 0.5), frame(0.01, fingers: 3, x: 0.48)]
    for step in 1...50 {
      let noise = step.isMultiple(of: 2) ? 0.002 : -0.002
      let position = 0.48 - Double(step) * 0.0005 + noise
      frames.append(frame(0.01 + Double(step) * 0.01, fingers: 3, x: position))
    }
    let offsets = run(frames).compactMap { update -> Double? in
      guard case .moved(let offset) = update else { return nil }
      return offset
    }
    let largestStepBack = zip(offsets, offsets.dropFirst()).map { $1 - $0 }.max() ?? 0
    #expect(offsets.count == 50)
    #expect(largestStepBack < 0.0002)
    #expect(offsets.last ?? 0 < -0.02, "it still follows the fingers")
  }

  @Test func aVerticalContactIsIgnoredUntilTheFingersLift() {
    var recognizer = SwipeRecognizer()
    var updates: [SwipeUpdate] = []
    for frame in [
      frame(0, fingers: 3, x: 0.5, y: 0.2),
      frame(0.01, fingers: 3, x: 0.5, y: 0.3),
      frame(0.02, fingers: 3, x: 0.2, y: 0.3),  // sideways afterwards: still ignored
      frame(0.03, fingers: 2, x: 0.2),
      frame(0.04, fingers: 3, x: 0.2),
      frame(0.05, fingers: 3, x: 0.3),
    ] {
      updates += recognizer.feed(frame)
    }
    #expect(updates == [.began])  // only the second contact counts
  }

  @Test(arguments: [2, 4])
  func otherFingerCountsAreIgnored(count: Int) {
    let updates = run([
      frame(0, fingers: count, x: 0.5), frame(0.01, fingers: count, x: 0.2),
    ])
    #expect(updates.isEmpty)
  }

  @Test func aFourFingerRecognizerTakesFourFingers() {
    let updates = run([frame(0, fingers: 4, x: 0.5), frame(0.01, fingers: 4, x: 0.6)], fingers: 4)
    #expect(updates.first == .began)
  }

  @Test func aFourthFingerEndsAThreeFingerSwipe() {
    let updates = run([
      frame(0, fingers: 3, x: 0.5), frame(0.01, fingers: 3, x: 0.6),
      frame(0.02, fingers: 4, x: 0.6),
    ])
    guard case .ended = updates.last else {
      Issue.record("expected an end, got \(updates)")
      return
    }
  }

  @Test func reversingThroughTheStartGivesNegativeOffsets() {
    let updates = run([
      frame(0, fingers: 3, x: 0.5), frame(0.01, fingers: 3, x: 0.6),
      frame(0.02, fingers: 3, x: 0.4),
    ])
    guard case .moved(let offset) = updates.last else {
      Issue.record("expected a move, got \(updates)")
      return
    }
    #expect(offset < 0)
  }

  @Test func theVelocityOnlyLooksAtTheLastMoments() {
    // Fast at first, then the fingers stop for longer than the window before lifting.
    let updates = run([
      frame(0, fingers: 3, x: 0.5), frame(0.01, fingers: 3, x: 0.3),
      frame(0.10, fingers: 3, x: 0.3), frame(0.12, fingers: 3, x: 0.3),
      frame(0.13, fingers: 2, x: 0.3),
    ])
    #expect(updates.last == .ended(velocity: 0))
  }

  @Test func aSwipeWithASingleFrameEndsWithNoVelocity() {
    let updates = run([
      frame(0, fingers: 3, x: 0.5), frame(0.01, fingers: 3, x: 0.6),
      frame(0.02, fingers: 0, x: 0),
    ])
    #expect(updates.last == .ended(velocity: 0))
  }
}
