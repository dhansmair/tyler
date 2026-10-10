import CoreGraphics
import MWMCore

/// Steps windows along their tracks over `duration`, one eased position per frame. Time comes
/// from an injected clock, so tests can drive an animation without sleeping. A zero duration
/// means "snap": callers then skip the animation and place windows directly.
@MainActor
public struct Animator {
  public static let defaultDuration = Duration.milliseconds(200)
  public static let defaultFrameInterval = Duration.milliseconds(16)

  public let duration: Duration
  public let frameInterval: Duration
  private let clock: any Clock<Duration>

  public init(
    duration: Duration = Animator.defaultDuration,
    frameInterval: Duration = Animator.defaultFrameInterval,
    clock: any Clock<Duration> = ContinuousClock()
  ) {
    self.duration = duration
    self.frameInterval = frameInterval
    self.clock = clock
  }

  /// An animator that never animates.
  public static var snap: Animator { Animator(duration: .zero) }

  /// How many frames an animation has; 0 means it snaps.
  public var stepCount: Int {
    guard frameInterval > .zero, duration > .zero else { return 0 }
    return max(1, Int((duration / frameInterval).rounded(.up)))
  }

  /// Runs the intermediate steps, calling `move` for every track on every frame but the last:
  /// the caller places windows at their final frames itself (with a full resize), so the last
  /// step is a wait only. Returns false if the task was cancelled, in which case the caller
  /// must not touch the windows on this animation's behalf any more.
  public func run(
    _ tracks: [Track],
    move: (WindowID, CGPoint) -> Void
  ) async -> Bool {
    let steps = stepCount
    for step in 0..<steps {
      do {
        try await clock.sleep(for: frameInterval)
      } catch {
        return false  // Cancelled: whoever cancelled has taken over the windows.
      }
      if Task.isCancelled { return false }
      guard step < steps - 1 else { break }
      let progress = Double(step + 1) / Double(steps)
      for track in tracks {
        move(track.id, track.position(at: progress))
      }
    }
    return !Task.isCancelled
  }
}
