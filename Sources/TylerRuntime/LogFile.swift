import Foundation

/// tylerd's log file when nothing else takes its output: launched by LaunchServices (`open`, a
/// login item), its stdout and stderr go to /dev/null.
package enum LogFile {
  /// Points stdout and stderr at `path`, emptied, if stderr goes to /dev/null or is closed. A
  /// terminal, a pipe, or the file `tyler start` opened is left alone. Returns whether it did.
  /// The previous log is kept (`keepPrevious`).
  package static func takeDiscardedOutput(to path: String) throws(LogFileError) -> Bool {
    guard isDiscarded(STDERR_FILENO) else { return false }
    let directory = (path as NSString).deletingLastPathComponent
    do {
      try FileManager.default.createDirectory(
        atPath: directory, withIntermediateDirectories: true)
    } catch {
      throw .cannotOpen(path, error.localizedDescription)
    }
    try keepPrevious(at: path)
    let file = open(path, O_WRONLY | O_CREAT | O_TRUNC | O_APPEND, 0o644)
    guard file >= 0 else { throw .cannotOpen(path, String(cString: strerror(errno))) }
    // With stdout or stderr closed, `open` returns the lowest free number, which is then the one
    // to keep.
    defer { if file > STDERR_FILENO { close(file) } }
    guard dup2(file, STDOUT_FILENO) >= 0, dup2(file, STDERR_FILENO) >= 0 else {
      throw .cannotOpen(path, String(cString: strerror(errno)))
    }
    return true
  }

  /// Renames the log at `path` to `<path>.1`, replacing the one there, so a restart after a bug
  /// doesn't lose its lines.
  package static func keepPrevious(at path: String) throws(LogFileError) {
    guard rename(path, path + ".1") == 0 || errno == ENOENT else {
      throw .cannotKeep(path, String(cString: strerror(errno)))
    }
  }

  static func isDiscarded(_ descriptor: Int32) -> Bool {
    var output = stat()
    guard fstat(descriptor, &output) == 0 else { return true }
    var null = stat()
    guard stat("/dev/null", &null) == 0 else { return false }
    return output.st_mode & S_IFMT == S_IFCHR && output.st_rdev == null.st_rdev
  }
}
