import Foundation

/// Smooths a noisy signal that is sometimes still and sometimes fast, such as fingers on a
/// trackpad: a low-pass filter whose cutoff rises with the signal's speed, so slow motion is
/// smoothed hard (no jitter) and fast motion hardly at all (no lag). This is the "1€ filter"
/// (Casiez, Roussel and Vogel, CHI 2012).
public struct OneEuroFilter: Equatable, Sendable {
  private struct Previous: Equatable, Sendable {
    let time: TimeInterval
    let value: Double
    let speed: Double
  }

  /// The cutoff, in hertz, when the signal is still. Lower smooths more and lags more.
  public let minimumCutoff: Double
  /// How fast the cutoff rises with speed (hertz per unit per second).
  public let speedCoefficient: Double
  /// The cutoff, in hertz, for smoothing the speed itself.
  public let speedCutoff: Double
  private var previous: Previous?

  public init(minimumCutoff: Double, speedCoefficient: Double, speedCutoff: Double = 1) {
    self.minimumCutoff = minimumCutoff
    self.speedCoefficient = speedCoefficient
    self.speedCutoff = speedCutoff
  }

  /// Takes the next raw value, at `time` in seconds, and returns the smoothed one. The first
  /// value passes through unchanged, and so does one that arrives no later than the one before.
  public mutating func filter(_ value: Double, at time: TimeInterval) -> Double {
    guard let previous, time > previous.time else {
      if previous == nil { self.previous = Previous(time: time, value: value, speed: 0) }
      return previous?.value ?? value
    }
    let interval = time - previous.time
    let rawSpeed = (value - previous.value) / interval
    let speed = Self.blend(
      rawSpeed, previous.speed, weight: Self.weight(cutoff: speedCutoff, interval: interval))
    let cutoff = minimumCutoff + speedCoefficient * abs(speed)
    let smoothed = Self.blend(
      value, previous.value, weight: Self.weight(cutoff: cutoff, interval: interval))
    self.previous = Previous(time: time, value: smoothed, speed: speed)
    return smoothed
  }

  /// How much of a new value an exponential smoother at `cutoff` takes after `interval`.
  private static func weight(cutoff: Double, interval: TimeInterval) -> Double {
    let timeConstant = 1 / (2 * Double.pi * cutoff)
    return 1 / (1 + timeConstant / interval)
  }

  private static func blend(_ new: Double, _ old: Double, weight: Double) -> Double {
    old + weight * (new - old)
  }
}
