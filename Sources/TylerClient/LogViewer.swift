import Foundation

/// Hands this process over to `tail`, so Ctrl-C and the exit status need no handling here. Not unit
/// tested; keep it thin.
package enum LogViewer {
  package static func show(_ path: String, isTerminal: Bool) throws(ViewerError) -> Never {
    guard FileManager.default.fileExists(atPath: path) else { throw .noLog(path) }
    let arguments = LogViewing.tailArguments(path: path, isTerminal: isTerminal)
    execv("/usr/bin/tail", arguments.map { strdup($0) } + [nil])
    throw .cannotRun(String(cString: strerror(errno)))
  }

  package enum ViewerError: Error, CustomStringConvertible {
    case noLog(String)
    case cannotRun(String)

    package var description: String {
      switch self {
      case .noLog(let path): "no log at \(path) (`tyler start` creates it)"
      case .cannotRun(let reason): "cannot run tail: \(reason)"
      }
    }
  }
}
