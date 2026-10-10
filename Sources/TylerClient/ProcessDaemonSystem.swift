import Foundation
import TylerCore

/// The real `DaemonSystem`: the socket, POSIX processes, the file system and the wall clock.
/// Not unit tested; keep it thin.
public struct ProcessDaemonSystem: DaemonSystem {
  private let client: IPCClient

  public init(client: IPCClient = IPCClient()) {
    self.client = client
  }

  public func send(_ request: Request) throws -> Response {
    try client.send(request)
  }

  /// Runs `executable` in a new session (so closing the terminal doesn't hang it up), with
  /// stdin from /dev/null and stdout and stderr in `logPath`, which starts empty. No other file
  /// descriptors are inherited.
  public func spawn(_ executable: String, logPath: String) throws(DaemonError) -> Int32 {
    let directory = (logPath as NSString).deletingLastPathComponent
    do {
      try FileManager.default.createDirectory(
        atPath: directory, withIntermediateDirectories: true)
    } catch {
      throw .spawnFailed("cannot create \(directory): \(error.localizedDescription)")
    }

    var actions: posix_spawn_file_actions_t?
    var attributes: posix_spawnattr_t?
    posix_spawn_file_actions_init(&actions)
    posix_spawnattr_init(&attributes)
    defer {
      posix_spawn_file_actions_destroy(&actions)
      posix_spawnattr_destroy(&attributes)
    }
    let setup = [
      posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0),
      posix_spawn_file_actions_addopen(
        &actions, STDOUT_FILENO, logPath, O_WRONLY | O_CREAT | O_TRUNC, 0o644),
      posix_spawn_file_actions_adddup2(&actions, STDOUT_FILENO, STDERR_FILENO),
      posix_spawnattr_setflags(
        &attributes, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT)),
    ]
    if let failure = setup.first(where: { $0 != 0 }) {
      throw .spawnFailed(String(cString: strerror(failure)))
    }

    let arguments: [UnsafeMutablePointer<CChar>?] = [strdup(executable), nil]
    defer {
      for argument in arguments { free(argument) }
    }
    var pid: pid_t = 0
    let result = posix_spawn(&pid, executable, &actions, &attributes, arguments, environ)
    guard result == 0 else { throw .spawnFailed(String(cString: strerror(result))) }
    return pid
  }

  public func terminate(_ pid: Int32) -> Bool {
    kill(pid, SIGTERM) == 0
  }

  /// Reaps the child if it has exited; a zombie would otherwise still count as running.
  public func childHasExited(_ pid: Int32) -> Bool {
    var status: Int32 = 0
    let result = waitpid(pid, &status, WNOHANG)
    return result == pid || (result == -1 && errno == ECHILD)
  }

  public func isRunning(_ pid: Int32) -> Bool {
    kill(pid, 0) == 0 || errno == EPERM
  }

  public func isExecutable(atPath path: String) -> Bool {
    FileManager.default.isExecutableFile(atPath: path)
  }

  public func modificationDate(ofFile path: String) -> Date? {
    do {
      return try FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date
    } catch {
      // A missing or unreadable binary has no date to compare; the stale check just skips it.
      return nil
    }
  }

  public func lastLines(ofFile path: String, count: Int) -> String {
    do {
      let text = try String(contentsOfFile: path, encoding: .utf8)
      return text.split(separator: "\n").suffix(count).joined(separator: "\n")
    } catch {
      return "(cannot read \(path): \(error.localizedDescription))"
    }
  }

  public var now: Date { Date() }

  public func pause(_ duration: Duration) {
    let (seconds, attoseconds) = duration.components
    Thread.sleep(forTimeInterval: Double(seconds) + Double(attoseconds) / 1e18)
  }
}
