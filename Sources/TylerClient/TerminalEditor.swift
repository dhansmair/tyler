import Foundation

/// Runs an editor in this terminal and waits for it. Not unit tested; keep it thin.
package enum TerminalEditor {
  /// `editor` is a shell command, as `$EDITOR` may hold arguments (`code --wait`). Creates the
  /// file first if it is missing: the config file is optional.
  package static func edit(_ path: String, with editor: String) throws(EditorError) {
    let files = FileManager.default
    do {
      if !files.fileExists(atPath: path) {
        let directory = (path as NSString).deletingLastPathComponent
        try files.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try Data().write(to: URL(fileURLWithPath: path))
      }
    } catch {
      throw .failed("cannot create \(path): \(error.localizedDescription)")
    }
    let status = try run(["/bin/sh", "-c", editor + #" "$1""#, "sh", path])
    guard status == 0 else { throw .failed("\(editor) exited with status \(status)") }
  }

  /// Not `Process`: it starts the child in a process group of its own, which isn't the terminal's
  /// foreground group, so an editor that reads the terminal is stopped (SIGTTIN) and hangs.
  /// `posix_spawn` keeps the child in tyler's group.
  private static func run(_ command: [String]) throws(EditorError) -> Int32 {
    let arguments = command.map { strdup($0) } + [nil]
    defer {
      for argument in arguments { free(argument) }
    }
    var pid: pid_t = 0
    let result = posix_spawn(&pid, command[0], nil, nil, arguments, environ)
    guard result == 0 else { throw .failed(String(cString: strerror(result))) }
    var status: Int32 = 0
    while waitpid(pid, &status, 0) == -1 {
      guard errno == EINTR else { throw .failed(String(cString: strerror(errno))) }
    }
    let signal = status & 0x7f
    return signal == 0 ? (status >> 8) & 0xff : 128 + signal
  }

  package enum EditorError: Error, CustomStringConvertible {
    case failed(String)

    package var description: String {
      switch self {
      case .failed(let message): message
      }
    }
  }
}
