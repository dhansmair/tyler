import Foundation
import TylerCore
import TylerProtocol
import TylerRuntime

/// Starts, stops and inspects the `tylerd` process for `tyler start|stop|restart|status`.
///
/// `start` launches the `Tyler.app` next to the `tyler` binary through LaunchServices, so it holds
/// its own Accessibility grant. Without one, it runs the `tylerd` there as a detached child,
/// whose grant is the terminal's (or whatever runs `tyler`).
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
  /// The `tylerd` that `start` runs when there is no `app`.
  package let serverPath: String
  package let logPath: String
  package let app: AppLaunch?
  var startTimeout: Duration = .seconds(10)
  var stopTimeout: Duration = .seconds(10)
  /// How long `start` waits for apps that haven't answered tylerd yet: it tries each again for
  /// about 2.5 s.
  var accessTimeout: Duration = .seconds(4)
  var pollInterval: Duration = .milliseconds(100)

  package init(
    system: any DaemonSystem, serverPath: String, logPath: String, app: AppLaunch? = nil
  ) {
    self.system = system
    self.serverPath = serverPath
    self.logPath = logPath
    self.app = app
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
      try withAccess(
        "tylerd is already running (pid \(status.pid))" + staleWarning(status), of: status)
    case .started(let status):
      try withAccess("started tylerd (pid \(status.pid)), output in \(logPath)", of: status)
    }
  }

  private func stopMessage() throws(DaemonError) -> String {
    switch try stop() {
    case .notRunning: "tylerd is not running"
    case .stopped(let pid, _): "stopped tylerd (pid \(pid))"
    }
  }

  /// Restarts without losing the arrangement: the old tylerd hands its workspaces over and the
  /// new one carries on. A tylerd too old to hand over is stopped normally instead, and so is one
  /// whose successor runs from elsewhere: that may hold another grant (the terminal's, another
  /// app's) or none yet, and couldn't take parked windows on until it is granted.
  private func restartMessage() throws(DaemonError) -> String {
    // Before stopping: a tylerd that handed over and has no successor leaves windows parked.
    let target = try launchTarget()
    let movesElsewhere = try runningStatus().map { $0.executablePath != executablePath(target) }
    let stopped = try stop(keepingWindows: movesElsewhere != true)
    switch (stopped, try start(target)) {
    case (_, .alreadyRunning(let status)):
      return try withAccess(
        "tylerd is already running (pid \(status.pid))" + staleWarning(status), of: status)
    case (.notRunning, .started(let status)):
      return try withAccess(
        "tylerd was not running; started it (pid \(status.pid)), output in \(logPath)",
        of: status)
    case (.stopped(let old, let keptWindows), .started(let status)):
      let note =
        if keptWindows {
          ""
        } else if movesElsewhere == true {
          "\n(the new tylerd runs from elsewhere, with a permission of its own, so the old one put "
            + "its windows back where they were)"
        } else {
          "\n(the old tylerd could not hand over, so its windows went back where they were)"
        }
      return try withAccess(
        "restarted tylerd (pid \(old) → \(status.pid)), output in \(logPath)" + note, of: status)
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
    if let access = status.access {
      lines.append("  access  \(access.summary)")
      if let problem = access.problem(app: status.appName) { lines.append("warning: " + problem) }
    }
    if let input = status.input { lines += InputListener.statusLines(input, now: system.now) }
    return lines.joined(separator: "\n") + staleWarning(status)
  }

  /// `report` with what tylerd's access to the windows adds to it, once it is settled: a note,
  /// or an error when it needs fixing. tylerd keeps running either way.
  private func withAccess(_ report: String, of status: ServerStatus) throws(DaemonError) -> String {
    guard let access = settledAccess(status) else { return report }
    if let problem = access.problem(app: status.appName) {
      throw .cannotReachWindows(report: report, problem: problem)
    }
    return access.note.map { report + "\nnote: " + $0 } ?? report
  }

  /// The server's access to the windows, after waiting while apps haven't answered it yet; `nil`
  /// from a server older than the check.
  private func settledAccess(_ status: ServerStatus) -> WindowAccess? {
    var access = status.access
    var waited = Duration.zero
    while access == .checking, waited < accessTimeout {
      system.pause(pollInterval)
      waited += pollInterval
      guard case .running(let fresh) = probe() else { break }
      access = fresh.access
    }
    return access
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

  /// Launches `target`, or what `launchTarget` finds, unless tylerd already runs.
  private func start(_ target: LaunchTarget? = nil) throws(DaemonError) -> StartOutcome {
    if let status = try runningStatus() { return .alreadyRunning(status) }
    let pid: Int32?
    if let target {
      pid = try launch(target)
    } else {
      pid = try launch(launchTarget())
    }
    var waited = Duration.zero
    while waited < startTimeout {
      system.pause(pollInterval)
      waited += pollInterval
      if let pid, system.childHasExited(pid) {
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
    if let app, status.executablePath == app.executablePath, isOutdated(app) {
      warning +=
        "\nwarning: \(app.path) is older than the tylerd next to it; run `make build`, then "
        + "`tyler restart`"
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
