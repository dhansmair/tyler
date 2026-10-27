package enum LogFileError: Error, CustomStringConvertible {
  case cannotOpen(String, String)
  case cannotKeep(String, String)

  package var description: String {
    switch self {
    case .cannotOpen(let path, let reason): "cannot open \(path): \(reason)"
    case .cannotKeep(let path, let reason): "cannot keep \(path) as \(path).1: \(reason)"
    }
  }
}
