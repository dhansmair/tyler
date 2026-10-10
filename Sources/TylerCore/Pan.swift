import CoreGraphics
import Foundation

/// The fingers on the trackpad at one moment: positions are normalized to the trackpad (0 to 1
/// on each axis, x growing to the right). Platform code converts touch events to this, so the
/// recognizer stays free of AppKit.
public struct TouchFrame: Equatable, Sendable {
  /// Seconds, from any fixed origin.
  public let time: TimeInterval
  public let positions: [CGPoint]

  public init(time: TimeInterval, positions: [CGPoint]) {
    self.time = time
    self.positions = positions
  }
}

/// What a horizontal pan did. Offsets and velocities are in trackpad widths: an offset of 0.25
/// means the fingers moved a quarter of the trackpad to the right since the pan began (negative
/// is to the left). Knows nothing about what the pan moves; that is up to whoever listens.
public enum PanUpdate: Equatable, Sendable {
  case began
  case moved(offset: Double)
  /// The fingers lifted (or more joined). `velocity` is in trackpad widths per second over the
  /// last moments of the pan.
  case ended(velocity: Double)
}

/// Turns touch frames into a horizontal pan with a given number of fingers. A pan starts once the
/// fingers have travelled `lockDistance` mostly sideways; a contact that travels mostly vertically
/// first is ignored until the fingers lift, which leaves vertical swipes to macOS. Any change in
/// the number of fingers ends a pan, and fingers land and lift one at a time, so a 3-finger pan is
/// framed by 1- and 2-finger frames that don't count.
public struct PanRecognizer: Equatable, Sendable {
  private enum State: Equatable, Sendable {
    case idle
    /// The right number of fingers are down, but they haven't moved far enough to decide.
    case pending(start: CGPoint)
    /// Moving sideways. `samples` holds recent (time, offset) pairs for the velocity.
    case panning(start: CGPoint, samples: [Sample])
    /// Moved vertically first: ignored until the number of fingers changes.
    case rejected
  }

  private struct Sample: Equatable, Sendable {
    let time: TimeInterval
    let offset: Double
  }

  public let fingers: Int
  /// How far, in trackpad widths, the fingers must move before the pan's axis is decided.
  public let lockDistance: Double
  /// How far back, in seconds, the release velocity looks.
  public let velocityWindow: TimeInterval
  private var state = State.idle

  public init(fingers: Int = 3, lockDistance: Double = 0.03, velocityWindow: TimeInterval = 0.05) {
    self.fingers = fingers
    self.lockDistance = lockDistance
    self.velocityWindow = velocityWindow
  }

  /// Whether a pan is in progress.
  public var isPanning: Bool {
    if case .panning = state { return true }
    return false
  }

  /// Takes the next frame and returns what the pan did in it: nothing, `.began` followed by the
  /// first `.moved`, a `.moved`, or `.ended`.
  public mutating func feed(_ frame: TouchFrame) -> [PanUpdate] {
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
        let offset = Double(across)
        state = .panning(start: start, samples: [Sample(time: frame.time, offset: offset)])
        return [.began, .moved(offset: offset)]
      }
      if abs(along) >= lockDistance { state = .rejected }
      return []
    case .panning(let start, var samples):
      let offset = Double(mean.x - start.x)
      samples.append(Sample(time: frame.time, offset: offset))
      samples.removeAll { $0.time < frame.time - velocityWindow }
      state = .panning(start: start, samples: samples)
      return [.moved(offset: offset)]
    }
  }

  /// The fingers changed: a pan in progress ends, anything else starts over.
  private mutating func end() -> [PanUpdate] {
    defer { state = .idle }
    guard case .panning(_, let samples) = state else { return [] }
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
