import Foundation
import TylerCore

/// What `DaemonController` needs from the operating system: the server's socket, processes,
/// files and time. A protocol so tests can fake the server process and the clock.
public protocol DaemonSystem {
  /// Sends one request to the server. Throws `IPCClientError.serverNotRunning` when nothing
  /// listens on the socket.
  func send(_ request: Request) throws -> Response
  /// Starts `executable` in the background, detached from the terminal, with its output going
  /// to `logPath`. Returns its pid.
  func spawn(_ executable: String, logPath: String) throws(DaemonError) -> Int32
  /// Asks a process to quit (SIGTERM). Returns whether the signal was sent.
  func terminate(_ pid: Int32) -> Bool
  /// Whether a process this client spawned has already exited.
  func childHasExited(_ pid: Int32) -> Bool
  /// Whether any process with this pid exists.
  func isRunning(_ pid: Int32) -> Bool
  func isExecutable(atPath path: String) -> Bool
  /// `nil` if the file doesn't exist.
  func modificationDate(ofFile path: String) -> Date?
  /// The last `count` lines of a text file, or a note saying why it can't be read.
  func lastLines(ofFile path: String, count: Int) -> String
  var now: Date { get }
  func pause(_ duration: Duration)
}

public enum DaemonError: Error, Equatable, Sendable, CustomStringConvertible {
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

  public var description: String {
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
      "cannot send SIGTERM to tylerd (pid \(pid))"
    case .stillRunning(let pid):
      "tylerd (pid \(pid)) is still running; it may be stuck putting windows back "
        + "(`kill -9 \(pid)` stops it, but leaves parked windows in the corner)"
    }
  }
}

/// Starts, stops and inspects the `tylerd` process for `tyler start|stop|restart|status`.
///
/// `start` launches the `tylerd` next to the `tyler` binary as a detached child. Accessibility
/// permission belongs to the app responsible for a process, which stays the terminal (or
/// whatever runs `tyler`), so a rebuilt `tylerd` needs no new permission.
public struct DaemonController {
  private enum Probe {
    case notRunning
    case running(ServerStatus)
    case outdated
    case unresponsive
  }

  private enum StartOutcome {
    case alreadyRunning(ServerStatus)
    case started(ServerStatus)
  }

  private enum StopOutcome {
    case notRunning
    case stopped(Int32)
  }

  public let system: any DaemonSystem
  /// The `tylerd` that `start` launches.
  public let serverPath: String
  public let logPath: String
  var startTimeout: Duration = .seconds(10)
  var stopTimeout: Duration = .seconds(10)
  var pollInterval: Duration = .milliseconds(100)

  public init(system: any DaemonSystem, serverPath: String, logPath: String) {
    self.system = system
    self.serverPath = serverPath
    self.logPath = logPath
  }

  /// The `tylerd` in the same folder as the `tyler` binary at `client`, after resolving
  /// symlinks: a debug `tyler` starts the debug `tylerd`, an installed one the installed one.
  public static func serverPath(nextTo client: URL) -> String {
    client.resolvingSymlinksInPath().deletingLastPathComponent()
      .appendingPathComponent("tylerd").path
  }

  public func run(_ command: DaemonCommand) -> Response {
    do {
      switch command {
      case .start: return .message(try startMessage())
      case .stop: return .message(try stopMessage())
      case .restart: return .message(try restartMessage())
      case .status: return .message(try statusReport())
      }
    } catch {
      return .error(error.description)
    }
  }

  // MARK: - Commands

  private func startMessage() throws(DaemonError) -> String {
    switch try start() {
    case .alreadyRunning(let status):
      "tylerd is already running (pid \(status.pid))" + staleWarning(status)
    case .started(let status):
      "started tylerd (pid \(status.pid)), output in \(logPath)"
    }
  }

  private func stopMessage() throws(DaemonError) -> String {
    switch try stop() {
    case .notRunning: "tylerd is not running"
    case .stopped(let pid): "stopped tylerd (pid \(pid))"
    }
  }

  private func restartMessage() throws(DaemonError) -> String {
    let stopped = try stop()
    switch (stopped, try start()) {
    case (_, .alreadyRunning(let status)):
      return "tylerd is already running (pid \(status.pid))" + staleWarning(status)
    case (.notRunning, .started(let status)):
      return "tylerd was not running; started it (pid \(status.pid)), output in \(logPath)"
    case (.stopped(let old), .started(let status)):
      return "restarted tylerd (pid \(old) → \(status.pid)), output in \(logPath)"
    }
  }

  private func statusReport() throws(DaemonError) -> String {
    let status: ServerStatus
    switch probe() {
    case .running(let running): status = running
    case .notRunning: throw .notRunning
    case .outdated: throw .outdatedServer
    case .unresponsive: throw .unresponsive
    }
    let uptime = Self.describe(uptime: system.now.timeIntervalSince(status.startedAt))
    let lines = [
      "tylerd is running (pid \(status.pid), up \(uptime))",
      "  binary  \(status.executablePath)",
      "  config  \(status.configPath)",
      "  tiling  \(Self.describe(status.tiling))",
    ]
    return lines.joined(separator: "\n") + staleWarning(status)
  }

  // MARK: - Steps

  private func probe() -> Probe {
    do {
      guard case .status(let status) = try system.send(.status) else { return .outdated }
      return .running(status)
    } catch IPCClientError.serverNotRunning {
      return .notRunning
    } catch {
      return .unresponsive
    }
  }

  private func start() throws(DaemonError) -> StartOutcome {
    switch probe() {
    case .running(let status): return .alreadyRunning(status)
    case .outdated: throw .outdatedServer
    case .unresponsive: throw .unresponsive
    case .notRunning: break
    }
    guard system.isExecutable(atPath: serverPath) else { throw .missingServer(serverPath) }
    let pid = try system.spawn(serverPath, logPath: logPath)
    var waited = Duration.zero
    while waited < startTimeout {
      system.pause(pollInterval)
      waited += pollInterval
      if system.childHasExited(pid) {
        throw .exitedAtStartup(log: system.lastLines(ofFile: logPath, count: 10))
      }
      switch probe() {
      case .running(let status): return .started(status)
      case .outdated: throw .outdatedServer
      case .notRunning, .unresponsive: continue
      }
    }
    throw .noAnswer(pid: pid, logPath: logPath)
  }

  /// Sends SIGTERM, which runs tylerd's normal shutdown (windows go back where they were), and
  /// waits for the process to end.
  private func stop() throws(DaemonError) -> StopOutcome {
    let pid: Int32
    switch probe() {
    case .running(let status): pid = status.pid
    case .notRunning: return .notRunning
    case .outdated: throw .outdatedServer
    case .unresponsive: throw .unresponsive
    }
    guard system.terminate(pid) else { throw .cannotSignal(pid) }
    var waited = Duration.zero
    while system.isRunning(pid) {
      guard waited < stopTimeout else { throw .stillRunning(pid) }
      system.pause(pollInterval)
      waited += pollInterval
    }
    return .stopped(pid)
  }

  // MARK: - Text

  /// Empty unless the running binary has been rebuilt since the server started.
  private func staleWarning(_ status: ServerStatus) -> String {
    guard let built = status.executableModified,
      let current = system.modificationDate(ofFile: status.executablePath), current > built
    else { return "" }
    return
      "\nwarning: tylerd has been rebuilt since it started; run `tyler restart` to use the new build"
  }

  static func describe(uptime seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds))
    let (days, hours, minutes) = (total / 86_400, total / 3_600 % 24, total / 60 % 60)
    if days > 0 { return "\(days)d \(hours)h" }
    if hours > 0 { return "\(hours)h \(minutes)m" }
    if minutes > 0 { return "\(minutes)m" }
    return "\(total)s"
  }

  private static func describe(_ tiling: ServerStatus.Tiling) -> String {
    switch tiling {
    case .on: "on"
    case .off: "off"
    case .waitingForPermission: "waiting for Accessibility permission"
    }
  }
}
