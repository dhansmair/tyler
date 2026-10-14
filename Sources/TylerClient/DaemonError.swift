package enum DaemonError: Error, Equatable, Sendable, CustomStringConvertible {
  /// A server answers, but not to `status`: it was built before `status` existed.
  case outdatedServer
  /// The socket accepts connections, but the server didn't reply in time.
  case unresponsive
  case notRunning
  case missingServer(String)
  case spawnFailed(String)
  case exitedAtStartup(log: String)
  case noAnswer(pid: Int32, logPath: String)
  case cannotSignal(Int32)
  case stillRunning(Int32)

  package var description: String {
    switch self {
    case .outdatedServer:
      "a tylerd from an older build is running, and it can't be stopped from here; stop it with "
        + "`pkill tylerd` (or Ctrl-C in its terminal), then run `tyler start`"
    case .unresponsive:
      "tylerd is running but did not answer"
    case .notRunning:
      "tylerd is not running"
    case .missingServer(let path):
      "cannot find tylerd at \(path) (tyler starts the tylerd in its own folder)"
    case .spawnFailed(let reason):
      "cannot start tylerd: \(reason)"
    case .exitedAtStartup(let log):
      "tylerd exited right after starting" + (log.isEmpty ? "" : ":\n" + log)
    case .noAnswer(let pid, let logPath):
      "tylerd (pid \(pid)) started but did not answer; see \(logPath)"
    case .cannotSignal(let pid):
      "cannot signal tylerd (pid \(pid))"
    case .stillRunning(let pid):
      "tylerd (pid \(pid)) is still running; it may be stuck putting windows back "
        + "(`kill -9 \(pid)` stops it, but leaves parked windows at the right edge)"
    }
  }
}
