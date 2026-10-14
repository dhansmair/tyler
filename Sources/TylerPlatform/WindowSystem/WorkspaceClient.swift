import Darwin

/// `NSWorkspace` and `NSRunningApplication`, one to one and nothing else, so the logic above them
/// can be tested against a fake.
@MainActor
protocol WorkspaceClient: AnyObject {
  var runningApps: [RunningApp] { get }
  var frontmostProcessID: pid_t? { get }
  /// tylerd's own.
  var ownProcessID: pid_t { get }
  func runningApp(_ processID: pid_t) -> RunningApp?

  /// Tells the handlers when an app launches, comes to the front, or quits.
  func start(
    launched: @escaping @MainActor @Sendable (pid_t) -> Void,
    activated: @escaping @MainActor @Sendable (pid_t) -> Void,
    quit: @escaping @MainActor @Sendable () -> Void)
  func stop()
}
