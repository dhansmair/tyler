import CoreGraphics
import Foundation

/// Turns touch frames into a horizontal swipe with a given number of fingers. A swipe starts once the
/// fingers have travelled `lockDistance` mostly sideways, and its offset counts from there, so the
/// content doesn't jump when it starts to move. A contact that travels mostly vertically first is
/// ignored until the fingers lift, which leaves vertical swipes to macOS. Any change in the number
/// of fingers ends a swipe, and fingers land and lift one at a time, so a 3-finger swipe is framed by
/// 1- and 2-finger frames that don't count.
///
/// Offsets are smoothed with a `OneEuroFilter`: one trackpad width moves the content several
/// display widths, so the sensor's jitter would otherwise make slowly moving windows twitch. The
/// release velocity comes from the raw positions.
package struct SwipeRecognizer: Equatable, Sendable {
  private enum State: Equatable, Sendable {
    case idle
    /// The right number of fingers are down, but they haven't moved far enough to decide.
    case pending(start: CGPoint)
    /// Moving sideways. `samples` holds recent (time, offset) pairs for the velocity.
    case swiping(start: CGPoint, samples: [Sample], smoothing: OneEuroFilter)
    /// Moved vertically first: ignored until the number of fingers changes.
    case rejected
  }

  private struct Sample: Equatable, Sendable {
    let time: TimeInterval
    let offset: Double
  }

  package let fingers: Int
  /// How far, in trackpad widths, the fingers must move before the swipe's axis is decided.
  let lockDistance: Double
  /// How far back, in seconds, the release velocity looks.
  let velocityWindow: TimeInterval
  private var state = State.idle

  /// Hard smoothing while the fingers move slowly (a 2 Hz cutoff), rising to about 30 Hz at the
  /// speed of a quick swipe (1.5 trackpad widths per second).
  package static let smoothing = OneEuroFilter(minimumCutoff: 2, speedCoefficient: 20)

  package init(
    fingers: Int = 3, lockDistance: Double = 0.015, velocityWindow: TimeInterval = 0.05
  ) {
    self.fingers = fingers
    self.lockDistance = lockDistance
    self.velocityWindow = velocityWindow
  }

  /// Whether a swipe is in progress.
  var isSwiping: Bool {
    if case .swiping = state { return true }
    return false
  }

  /// Takes the next frame and returns what the swipe did in it: nothing, `.began`, a `.moved`, or
  /// `.ended`.
  package mutating func feed(_ frame: TouchFrame) -> [SwipeUpdate] {
    guard frame.positions.count == fingers, let mean = Self.mean(of: frame.positions) else {
      return end()
    }
    switch state {
    case .idle:
      state = .pending(start: mean)
      return []
    case .rejected:
      return []
    case .pending(let start):
      let across = mean.x - start.x
      let along = mean.y - start.y
      if abs(across) >= lockDistance, abs(across) > abs(along) {
        var smoothing = Self.smoothing
        _ = smoothing.filter(0, at: frame.time)
        state = .swiping(
          start: mean, samples: [Sample(time: frame.time, offset: 0)], smoothing: smoothing)
        return [.began]
      }
      if abs(along) >= lockDistance { state = .rejected }
      return []
    case .swiping(let start, var samples, var smoothing):
      let offset = Double(mean.x - start.x)
      samples.append(Sample(time: frame.time, offset: offset))
      samples.removeAll { $0.time < frame.time - velocityWindow }
      let smoothed = smoothing.filter(offset, at: frame.time)
      state = .swiping(start: start, samples: samples, smoothing: smoothing)
      return [.moved(offset: smoothed)]
    }
  }

  /// The fingers changed: a swipe in progress ends, anything else starts over.
  private mutating func end() -> [SwipeUpdate] {
    defer { state = .idle }
    guard case .swiping(_, let samples, _) = state else { return [] }
    return [.ended(velocity: Self.velocity(of: samples))]
  }

  private static func velocity(of samples: [Sample]) -> Double {
    guard let first = samples.first, let last = samples.last, last.time > first.time else {
      return 0
    }
    return (last.offset - first.offset) / (last.time - first.time)
  }

  private static func mean(of positions: [CGPoint]) -> CGPoint? {
    guard !positions.isEmpty else { return nil }
    let count = CGFloat(positions.count)
    return CGPoint(
      x: positions.map(\.x).reduce(0, +) / count, y: positions.map(\.y).reduce(0, +) / count)
  }
}
