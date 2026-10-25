import Foundation
import TylerCore
import TylerProtocol

/// The real `DaemonSystem`: the socket, POSIX processes, the file system and the wall clock.
/// Not unit tested; keep it thin.
package struct ProcessDaemonSystem: DaemonSystem {
  private let client: IPCClient

  package init(client: IPCClient = IPCClient()) {
    self.client = client
  }

  package func send(_ request: Request) throws -> Response {
    try client.send(request)
  }

  /// Runs `executable` in a new session (so closing the terminal doesn't hang it up), with
  /// stdin from /dev/null and stdout and stderr in `logPath`, which starts empty. No other file
  /// descriptors are inherited.
  package func spawn(_ executable: String, logPath: String) throws(DaemonError) -> Int32 {
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

  package func launchApp(_ path: String, environment: [String: String]) throws(DaemonError) {
    let open = Process()
    open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    let variables = environment.sorted { $0.key < $1.key }.flatMap { ["--env", "\($0)=\($1)"] }
    open.arguments = ["-n", "-g"] + variables + [path]
    let errors = Pipe()
    open.standardError = errors
    do {
      try open.run()
    } catch {
      throw .spawnFailed("cannot run open: \(error.localizedDescription)")
    }
    open.waitUntilExit()
    guard open.terminationStatus == 0 else {
      let data = errors.fileHandleForReading.readDataToEndOfFile()
      let output = String(bytes: data, encoding: .utf8) ?? ""
      throw .spawnFailed(
        "open \(path) failed: \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
    }
  }

  package func appInfo(atPath path: String) -> AppInfo? {
    let plist = path + "/Contents/Info.plist"
    guard let data = FileManager.default.contents(atPath: plist) else { return nil }
    let values: [String: Any]
    do {
      guard
        let read = try PropertyListSerialization.propertyList(from: data, format: nil)
          as? [String: Any]
      else { return nil }
      values = read
    } catch {
      return nil
    }
    return AppInfo(
      build: values["CFBundleVersion"] as? String,
      installsInApplications: values["TylerInstallsInApplications"] as? Bool ?? false,
      bundleID: values["CFBundleIdentifier"] as? String,
      isSignedAdHoc: values["TylerSignedAdHoc"] as? Bool ?? false)
  }

  package func stageApp(
    from source: String, nextTo destination: String
  ) throws(DaemonError) -> String {
    let files = FileManager.default
    let folder = (destination as NSString).deletingLastPathComponent
    let staged = folder + "/." + (destination as NSString).lastPathComponent + ".new"
    do {
      try files.createDirectory(atPath: folder, withIntermediateDirectories: true)
      if files.fileExists(atPath: staged) { try files.removeItem(atPath: staged) }
      try files.copyItem(atPath: source, toPath: staged)
    } catch {
      throw .installFailed(staged, error.localizedDescription)
    }
    return staged
  }

  package func replaceApp(at destination: String, with staged: String) throws(DaemonError) {
    let files = FileManager.default
    do {
      if files.fileExists(atPath: destination) {
        _ = try files.replaceItemAt(
          URL(fileURLWithPath: destination), withItemAt: URL(fileURLWithPath: staged))
      } else {
        try files.moveItem(atPath: staged, toPath: destination)
      }
    } catch {
      throw .installFailed(destination, error.localizedDescription)
    }
  }

  package func resetAccessibility(bundleID: String) throws(DaemonError) -> Bool {
    let tccutil = Process()
    tccutil.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
    tccutil.arguments = ["reset", "Accessibility", bundleID]
    let errors = Pipe()
    tccutil.standardOutput = FileHandle.nullDevice
    tccutil.standardError = errors
    do {
      try tccutil.run()
    } catch {
      throw .resetFailed(bundleID, error.localizedDescription)
    }
    tccutil.waitUntilExit()
    guard tccutil.terminationStatus == 0 else {
      let data = errors.fileHandleForReading.readDataToEndOfFile()
      let output = String(bytes: data, encoding: .utf8) ?? ""
      // What it says for a bundle ID LaunchServices doesn't know (OSStatus -10814, measured).
      if output.contains("No such bundle identifier") { return false }
      throw .resetFailed(bundleID, output.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    return true
  }

  package func terminate(_ pid: Int32) -> Bool {
    kill(pid, SIGTERM) == 0
  }

  package func requestHandOver(_ pid: Int32, puttingWindowsBack: Bool) -> Bool {
    kill(pid, puttingWindowsBack ? SIGUSR2 : SIGUSR1) == 0
  }

  /// Reaps the child if it has exited; a zombie would otherwise still count as running.
  package func childHasExited(_ pid: Int32) -> Bool {
    var status: Int32 = 0
    let result = waitpid(pid, &status, WNOHANG)
    return result == pid || (result == -1 && errno == ECHILD)
  }

  package func isRunning(_ pid: Int32) -> Bool {
    kill(pid, 0) == 0 || errno == EPERM
  }

  package func isExecutable(atPath path: String) -> Bool {
    FileManager.default.isExecutableFile(atPath: path)
  }

  package func modificationDate(ofFile path: String) -> Date? {
    do {
      return try FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date
    } catch {
      // A missing or unreadable binary has no date to compare; the stale check just skips it.
      return nil
    }
  }

  package func lastLines(ofFile path: String, count: Int) -> String {
    do {
      let text = try String(contentsOfFile: path, encoding: .utf8)
      return text.split(separator: "\n").suffix(count).joined(separator: "\n")
    } catch {
      return "(cannot read \(path): \(error.localizedDescription))"
    }
  }

  package var now: Date { Date() }

  package func pause(_ duration: Duration) {
    let (seconds, attoseconds) = duration.components
    Thread.sleep(forTimeInterval: Double(seconds) + Double(attoseconds) / 1e18)
  }
}
