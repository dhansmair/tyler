import Darwin

/// The apps that timed out lately, whose windows are left alone for a while: each call to an app
/// that doesn't answer waits the full Accessibility timeout, so placing its windows one by one on
/// every switch would hold up tylerd for a second per window.
struct UnresponsiveApps {
  static let pause = Duration.seconds(5)

  private var timedOut: [pid_t: ContinuousClock.Instant] = [:]

  /// Notes that `processID` timed out at `now`; `true` if it wasn't skipped already.
  mutating func noteTimeout(of processID: pid_t, at now: ContinuousClock.Instant) -> Bool {
    let wasSkipped = isSkipped(processID, at: now)
    timedOut[processID] = now
    return !wasSkipped
  }

  func isSkipped(_ processID: pid_t, at now: ContinuousClock.Instant) -> Bool {
    guard let instant = timedOut[processID] else { return false }
    return now < instant + Self.pause
  }

  mutating func forget(_ processID: pid_t) {
    timedOut[processID] = nil
  }
}
