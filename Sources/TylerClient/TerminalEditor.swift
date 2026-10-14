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
      let process = try Process.run(
        URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", editor + #" "$1""#, "sh", path])
      process.waitUntilExit()
      guard process.terminationStatus == 0 else {
        throw EditorError.failed("\(editor) exited with status \(process.terminationStatus)")
      }
    } catch let error as EditorError {
      throw error
    } catch {
      throw .failed("cannot open \(path): \(error.localizedDescription)")
    }
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
