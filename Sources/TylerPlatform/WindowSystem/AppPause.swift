import TylerServer

/// Whether an app that timed out is left alone: each call to an app that doesn't answer waits the
/// full Accessibility timeout, so placing its windows one by one on every switch would hold up
/// tylerd for a second per window.
struct AppPause {
  static let length = Duration.seconds(5)

  private let clock: any Clock<Duration>
  /// Set once the app timed out: whether its pause is over.
  private var isOver: (() -> Bool)?

  init(clock: any Clock<Duration>) {
    self.clock = clock
  }

  var isOn: Bool { isOver.map { !$0() } ?? false }

  /// Refuses at once while the pause is on, instead of waiting out the timeout again.
  func refuseIfOn() throws(WindowSystemError) {
    guard !isOn else { throw .refused("its app didn't answer a moment ago") }
  }

  /// Starts the pause from now, or starts it again. Returns whether it was off.
  mutating func start() -> Bool {
    let wasOn = isOn
    let clock = clock  // Swift opens the existential from a local, not from the stored property.
    isOver = Self.deadline(Self.length, on: clock)
    return !wasOn
  }

  private static func deadline(_ duration: Duration, on clock: some Clock<Duration>) -> () -> Bool {
    let end = clock.now.advanced(by: duration)
    return { clock.now >= end }
  }
}
