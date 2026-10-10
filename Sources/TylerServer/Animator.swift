import CoreGraphics
import TylerCore

/// Moves windows along their tracks over `duration`, one eased position per frame. Progress
/// comes from the elapsed time, not the frame count, so a slow app makes the slide coarser but
/// never longer. Time comes from an injected clock, so tests can drive an animation without
/// sleeping. A zero duration means "snap": callers then skip the animation and place windows
/// directly.
@MainActor
public struct Animator {
  public static let defaultDuration = Duration.milliseconds(250)
  /// Short enough for a 120 Hz display; with several windows the AX calls set the real pace.
  public static let defaultFrameInterval = Duration.milliseconds(8)

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

  /// The most frames an animation has (fewer when moving the windows takes longer than a
  /// frame); 0 means it snaps.
  public var stepCount: Int {
    guard frameInterval > .zero, duration > .zero else { return 0 }
    return max(1, Int((duration / frameInterval).rounded(.up)))
  }

  /// Runs the intermediate steps, calling `move` for every track on every frame until the
  /// duration is up: the caller places windows at their final frames itself (with a full
  /// resize), so the last frame is a wait only. Returns false if the task was cancelled, in
  /// which case the caller must not touch the windows on this animation's behalf any more.
  public func run(
    _ tracks: [Track],
    move: (WindowID, CGPoint) -> Void
  ) async -> Bool {
    let clock = clock  // Swift opens the existential from a local, not from the stored property.
    return await run(tracks, timedBy: clock, move: move)
  }

  private func run(
    _ tracks: [Track],
    timedBy clock: some Clock<Duration>,
    move: (WindowID, CGPoint) -> Void
  ) async -> Bool {
    let start = clock.now
    var deadline = start
    while true {
      // Frames sit on a fixed grid; one that overran skips the deadlines it missed.
      repeat {
        deadline = deadline.advanced(by: frameInterval)
      } while deadline <= clock.now
      do {
        try await clock.sleep(until: deadline, tolerance: nil)
      } catch {
        return false  // Cancelled: whoever cancelled has taken over the windows.
      }
      if Task.isCancelled { return false }
      let progress = start.duration(to: clock.now) / duration
      guard progress < 1 else { break }
      for track in tracks {
        move(track.id, track.position(at: progress))
      }
    }
    return !Task.isCancelled
  }
}
