import CoreGraphics
import Foundation
import Testing

@testable import TylerCore

@Suite("PanRecognizer")
struct PanRecognizerTests {
  /// `count` fingers side by side around (`x`, `y`), 0.1 apart vertically.
  private func frame(
    _ time: TimeInterval, fingers count: Int, x across: Double, y along: Double = 0.5
  ) -> TouchFrame {
    TouchFrame(
      time: time,
      positions: (0..<count).map { CGPoint(x: across, y: along + Double($0) * 0.1) })
  }

  /// Feeds every frame and collects what came out.
  private func run(_ frames: [TouchFrame], fingers: Int = 3) -> [PanUpdate] {
    var recognizer = PanRecognizer(fingers: fingers)
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
    #expect(updates.count == 4)
    #expect(updates[0] == .began)
    guard case .moved(let first) = updates[1], case .moved(let second) = updates[2],
      case .ended(let velocity) = updates[3]
    else {
      Issue.record("unexpected updates \(updates)")
      return
    }
    #expect(abs(first - -0.04) < 1e-9)
    #expect(abs(second - -0.10) < 1e-9)
    #expect(abs(velocity - -6) < 1e-6)  // 0.06 widths in 0.01 s
  }

  @Test func movingRightGivesPositiveOffsets() {
    let updates = run([
      frame(0, fingers: 3, x: 0.2), frame(0.01, fingers: 3, x: 0.3),
    ])
    #expect(updates.first == .began)
    guard case .moved(let offset) = updates.last else {
      Issue.record("expected a move, got \(updates)")
      return
    }
    #expect(abs(offset - 0.1) < 1e-9)
  }

  @Test func smallMovesDontBeginAPan() {
    let updates = run([
      frame(0, fingers: 3, x: 0.5), frame(0.01, fingers: 3, x: 0.52),
      frame(0.02, fingers: 0, x: 0),
    ])
    #expect(updates.isEmpty)
  }

  @Test func aVerticalContactIsIgnoredUntilTheFingersLift() {
    var recognizer = PanRecognizer()
    var updates: [PanUpdate] = []
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
    #expect(updates.first == .began)  // only the second contact counts
    #expect(updates.count == 2)
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

  @Test func aFourthFingerEndsAThreeFingerPan() {
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

  @Test func aPanWithASingleFrameEndsWithNoVelocity() {
    let updates = run([
      frame(0, fingers: 3, x: 0.5), frame(0.01, fingers: 3, x: 0.6),
      frame(0.02, fingers: 0, x: 0),
    ])
    #expect(updates.last == .ended(velocity: 0))
  }
}
