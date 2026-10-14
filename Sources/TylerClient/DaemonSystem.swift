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
  /// Asks a process to quit (SIGTERM). Returns whether the signal was sent.
  func terminate(_ pid: Int32) -> Bool
  /// Asks tylerd to quit and leave its windows where they are, writing its workspaces down for
  /// the next tylerd (SIGUSR1). Returns whether the signal was sent.
  func requestHandOver(_ pid: Int32) -> Bool
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
