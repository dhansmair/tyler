import Foundation
import TylerProtocol

/// What `DaemonController` needs from the operating system: the server's socket, processes,
/// files and time. A protocol so tests can fake the server process and the clock.
package protocol DaemonSystem {
  /// Sends one request to the server. Throws `IPCClientError.serverNotRunning` when nothing
  /// listens on the socket.
  func send(_ request: Request) throws -> Response
  /// Starts `executable` in the background, detached from the terminal, with its output going
  /// to `logPath`. Returns its pid.
  func spawn(_ executable: String, logPath: String) throws(DaemonError) -> Int32
  /// Launches the app at `path` through LaunchServices, in a new instance and without taking the
  /// focus, with `environment`; returns once it has been launched. tylerd opens its own log then.
  func launchApp(_ path: String, environment: [String: String]) throws(DaemonError)
  /// The `Info.plist` of the app at `path`; `nil` if there is none.
  func appInfo(atPath path: String) -> AppInfo?
  /// Copies the app at `source` next to `destination`, under a hidden name, creating the folder;
  /// returns where. `destination` stays as it was.
  func stageApp(from source: String, nextTo destination: String) throws(DaemonError) -> String
  /// Puts the staged app in place at `destination` in one step; on failure `destination` is left
  /// as it was.
  func replaceApp(at destination: String, with staged: String) throws(DaemonError)
  /// Removes the Accessibility entry of the app `bundleID` (`tccutil reset`), so macOS asks
  /// again. Only once the tylerd holding it has quit: taking a grant away from a running process
  /// can stop all input. `tccutil` finds the app through LaunchServices: returns false if no app
  /// with that ID is registered, which an app that was never launched isn't, and then there is
  /// no entry to reset either.
  func resetAccessibility(bundleID: String) throws(DaemonError) -> Bool
  /// Asks a process to quit (SIGTERM). Returns whether the signal was sent.
  func terminate(_ pid: Int32) -> Bool
  /// Asks tylerd to quit and write its workspaces down for the next tylerd, leaving its windows
  /// where they are (SIGUSR1) or `puttingWindowsBack` first (SIGUSR2). Returns whether the
  /// signal was sent.
  func requestHandOver(_ pid: Int32, puttingWindowsBack: Bool) -> Bool
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
