import Foundation
import TylerProtocol
import TylerRuntime

/// Starts, stops and inspects the `tylerd` process for `tyler start|stop|restart|status`.
///
/// `start` launches the `tylerd` next to the `tyler` binary as a detached child. Accessibility
/// permission belongs to the app responsible for a process, which stays the terminal (or
/// whatever runs `tyler`), so a rebuilt `tylerd` needs no new permission.
package struct DaemonController {
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
    /// `keptWindows` when tylerd handed its workspaces over instead of putting windows back.
    case stopped(Int32, keptWindows: Bool)
  }

  package let system: any DaemonSystem
  /// The `tylerd` that `start` launches.
  package let serverPath: String
  package let logPath: String
  var startTimeout: Duration = .seconds(10)
  var stopTimeout: Duration = .seconds(10)
  var pollInterval: Duration = .milliseconds(100)

  package init(system: any DaemonSystem, serverPath: String, logPath: String) {
    self.system = system
    self.serverPath = serverPath
    self.logPath = logPath
  }

  /// The `tylerd` in the same folder as the `tyler` binary at `client`, after resolving
  /// symlinks: a debug `tyler` starts the debug `tylerd`, an installed one the installed one.
  package static func serverPath(nextTo client: URL) -> String {
    client.resolvingSymlinksInPath().deletingLastPathComponent()
      .appendingPathComponent("tylerd").path
  }

  package func run(_ command: DaemonCommand) -> Response {
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
    case .stopped(let pid, _): "stopped tylerd (pid \(pid))"
    }
  }

  /// Restarts without losing the arrangement: the old tylerd hands its workspaces over and the
  /// new one carries on. A tylerd too old to hand over is stopped normally instead.
  private func restartMessage() throws(DaemonError) -> String {
    let stopped = try stop(keepingWindows: true)
    switch (stopped, try start()) {
    case (_, .alreadyRunning(let status)):
      return "tylerd is already running (pid \(status.pid))" + staleWarning(status)
    case (.notRunning, .started(let status)):
      return "tylerd was not running; started it (pid \(status.pid)), output in \(logPath)"
    case (.stopped(let old, let keptWindows), .started(let status)):
      let note =
        keptWindows
        ? "" : "\n(the old tylerd could not hand over, so its windows went back where they were)"
      return "restarted tylerd (pid \(old) → \(status.pid)), output in \(logPath)" + note
    }
  }

  private func statusReport() throws(DaemonError) -> String {
    guard let status = try runningStatus() else { throw .notRunning }
    let uptime = Self.describe(uptime: system.now.timeIntervalSince(status.startedAt))
    var lines = [
      "tylerd is running (pid \(status.pid), up \(uptime))",
      "  version \(status.version ?? "older than 0.1.0")",
      "  binary  \(status.executablePath)",
      "  config  \(status.configPath)",
    ]
    if let changes = status.configChanges, !changes.isEmpty {
      lines.append("          changed by `config set`: \(changes.joined(separator: ", "))")
    }
    lines.append("  tiling  \(Self.describe(status.tiling))")
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

  /// The running server's status, `nil` when none is running; a server that answers wrongly or
  /// not at all is an error.
  private func runningStatus() throws(DaemonError) -> ServerStatus? {
    switch probe() {
    case .running(let status): return status
    case .notRunning: return nil
    case .outdated: throw .outdatedServer
    case .unresponsive: throw .unresponsive
    }
  }

  private func start() throws(DaemonError) -> StartOutcome {
    if let status = try runningStatus() { return .alreadyRunning(status) }
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
  /// waits for the process to end. With `keepingWindows`, a tylerd that supports it is asked to
  /// hand over instead (SIGUSR1), leaving its windows where they are.
  private func stop(keepingWindows: Bool = false) throws(DaemonError) -> StopOutcome {
    guard let status = try runningStatus() else { return .notRunning }
    let pid = status.pid
    let handsOver = keepingWindows && status.keepsWindowsOnRestart == true
    let signalled = handsOver ? system.requestHandOver(pid) : system.terminate(pid)
    guard signalled else { throw .cannotSignal(pid) }
    var waited = Duration.zero
    while system.isRunning(pid) {
      guard waited < stopTimeout else { throw .stillRunning(pid) }
      system.pause(pollInterval)
      waited += pollInterval
    }
    return .stopped(pid, keptWindows: handsOver)
  }

  // MARK: - Text

  /// Empty unless the running binary has been rebuilt since the server started.
  /// Warnings about a running server that isn't the build next to this client: its binary was
  /// rebuilt since it started, or it is another version.
  private func staleWarning(_ status: ServerStatus) -> String {
    var warning = ""
    if isRebuilt(status) {
      warning +=
        "\nwarning: tylerd has been rebuilt since it started; run `tyler restart` to use the new build"
    }
    if status.version != TylerVersion.current {
      warning +=
        "\nwarning: tylerd is version \(status.version ?? "older than 0.1.0"), this tyler is "
        + "\(TylerVersion.current); run `tyler restart`"
    }
    return warning
  }

  /// Whether the server's binary on disk is newer than the one it started from.
  private func isRebuilt(_ status: ServerStatus) -> Bool {
    guard let built = status.executableModified,
      let current = system.modificationDate(ofFile: status.executablePath)
    else { return false }
    return current > built
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
