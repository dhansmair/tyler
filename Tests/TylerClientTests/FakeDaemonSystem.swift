import Foundation
import TylerCore
import TylerProtocol
import TylerRuntime

@testable import TylerClient

/// A pretend operating system: one server process that the controller can start and stop, a
/// clock that only moves on `pause`, and a few files.
final class FakeDaemonSystem: DaemonSystem {
  enum Server {
    case none
    case running(ServerStatus)
    /// Answers every request with an error, like a server built before `status` existed.
    case outdated
    /// Accepts connections but never replies.
    case hung
  }

  /// What a spawned server does.
  enum SpawnBehaviour {
    /// Answers `status` after this many pauses.
    case answersAfter(pauses: Int)
    case exitsAtOnce(log: String)
    case neverAnswers
    case fails(String)
  }

  /// What the running server does on SIGTERM.
  enum StopBehaviour {
    case exitsAfter(pauses: Int)
    case ignoresIt
    case cannotBeSignalled
  }

  static let serverPath = "/build/tylerd"
  static let appPath = "/build/Tyler.app"
  static let installedAppPath = "/home/Applications/Tyler.app"
  static let logPath = "/home/.tyler/tyler.log"
  static let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

  var server: Server = .none
  var spawnBehaviour: SpawnBehaviour = .answersAfter(pauses: 2)
  var stopBehaviour: StopBehaviour = .exitsAfter(pauses: 2)
  var executables: Set<String> = [serverPath]
  var modificationDates: [String: Date] = [serverPath: start]
  var nextPID: Int32 = 200
  /// What the running server reports about its access to the windows at each `status`, the last
  /// one from then on; `status(pid:)`'s when empty.
  var accessReports: [WindowAccess?] = []
  private(set) var now = start
  private(set) var spawned: [(executable: String, logPath: String)] = []
  private(set) var launchedApps: [(path: String, environment: [String: String])] = []
  /// Why `open` fails, if it does.
  var launchFailure: String?
  /// Each app's `Info.plist`, by path.
  var appInfos: [String: AppInfo] = [:]
  /// Why staging or putting a staged app in place fails, if it does.
  var stageFailure: String?
  var replaceFailure: String?
  private(set) var staged: [String] = []
  /// Apps put in place, and whether a server was running at the time.
  private(set) var replaced: [(destination: String, whileRunning: Bool)] = []
  private(set) var terminated: [Int32] = []
  /// Pids asked to hand over (SIGUSR1).
  private(set) var handedOver: [Int32] = []
  /// Pids asked to hand over with their windows put back (SIGUSR2).
  private(set) var handedOverPuttingWindowsBack: [Int32] = []
  private(set) var pauses = 0

  private var pendingStart: (pid: Int32, readyAt: Int)?
  private var exitedChild: Int32?
  private var stopping: (pid: Int32, goneAt: Int)?

  /// `keepsWindows: nil` is a server from before hand-over existed, `version: nil` one from
  /// before 0.1.0.
  static func status(
    pid: Int32, executablePath: String = serverPath, startedAt: Date = start,
    keepsWindows: Bool? = true, putsWindowsBack: Bool? = true,
    version: String? = TylerVersion.current, configChanges: [String]? = [],
    access: WindowAccess? = .ok, input: [InputListener]? = nil, appName: String? = nil
  ) -> ServerStatus {
    ServerStatus(
      pid: pid, executablePath: executablePath, executableModified: start, startedAt: startedAt,
      configPath: "/home/.config/tyler/tyler.toml", tiling: .on,
      keepsWindowsOnRestart: keepsWindows, putsWindowsBackOnHandOver: putsWindowsBack,
      version: version, configChanges: configChanges,
      access: access, input: input, appName: appName)
  }

  func send(_ request: Request) throws -> Response {
    switch server {
    case .none: throw IPCClientError.serverNotRunning("/home/.tyler/tyler.sock")
    case .running(var status):
      if let access = accessReports.first {
        status.access = access
        if accessReports.count > 1 { accessReports.removeFirst() }
      }
      return .status(status)
    case .outdated: return .error("malformed request")
    case .hung: throw IPCClientError.badReply
    }
  }

  func spawn(_ executable: String, logPath: String) throws(DaemonError) -> Int32 {
    if case .fails(let reason) = spawnBehaviour { throw .spawnFailed(reason) }
    spawned.append((executable, logPath))
    let pid = nextPID
    nextPID += 1
    switch spawnBehaviour {
    case .answersAfter(let count): pendingStart = (pid, pauses + count)
    case .exitsAtOnce: exitedChild = pid
    case .neverAnswers, .fails: break
    }
    return pid
  }

  /// The app behaves as `spawnBehaviour` says, except that it has no pid to watch, so exiting at
  /// once shows only as never answering.
  func launchApp(_ path: String, environment: [String: String]) throws(DaemonError) {
    if let launchFailure { throw .spawnFailed(launchFailure) }
    launchedApps.append((path, environment))
    let pid = nextPID
    nextPID += 1
    if case .answersAfter(let count) = spawnBehaviour { pendingStart = (pid, pauses + count) }
  }

  func appInfo(atPath path: String) -> AppInfo? { appInfos[path] }

  func stageApp(from source: String, nextTo destination: String) throws(DaemonError) -> String {
    if let stageFailure { throw .installFailed(destination, stageFailure) }
    let path = destination + ".new"
    staged.append(path)
    appInfos[path] = appInfos[source]
    return path
  }

  func replaceApp(at destination: String, with staged: String) throws(DaemonError) {
    if let replaceFailure { throw .installFailed(destination, replaceFailure) }
    var isRunning = false
    if case .running = server { isRunning = true }
    replaced.append((destination, isRunning))
    appInfos[destination] = appInfos[staged]
    executables.insert(destination + "/Contents/MacOS/tylerd")
  }

  func terminate(_ pid: Int32) -> Bool {
    guard quit(pid) else { return false }
    terminated.append(pid)
    return true
  }

  func requestHandOver(_ pid: Int32, puttingWindowsBack: Bool) -> Bool {
    guard quit(pid) else { return false }
    if puttingWindowsBack {
      handedOverPuttingWindowsBack.append(pid)
    } else {
      handedOver.append(pid)
    }
    return true
  }

  /// SIGTERM, SIGUSR1 and SIGUSR2 all end the server, following `stopBehaviour`.
  private func quit(_ pid: Int32) -> Bool {
    if case .cannotBeSignalled = stopBehaviour { return false }
    if case .exitsAfter(let count) = stopBehaviour { stopping = (pid, pauses + count) }
    return true
  }

  func childHasExited(_ pid: Int32) -> Bool { exitedChild == pid }

  func isRunning(_ pid: Int32) -> Bool {
    guard case .running(let status) = server else { return false }
    return status.pid == pid
  }

  func isExecutable(atPath path: String) -> Bool { executables.contains(path) }

  func modificationDate(ofFile path: String) -> Date? { modificationDates[path] }

  func lastLines(ofFile path: String, count: Int) -> String {
    guard path == Self.logPath, case .exitsAtOnce(let log) = spawnBehaviour else { return "" }
    return log
  }

  func pause(_ duration: Duration) {
    pauses += 1
    now += Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    if let (pid, readyAt) = pendingStart, pauses >= readyAt {
      server = .running(Self.status(pid: pid, startedAt: now))
      pendingStart = nil
    }
    if let (_, goneAt) = stopping, pauses >= goneAt {
      server = .none
      stopping = nil
    }
  }
}
