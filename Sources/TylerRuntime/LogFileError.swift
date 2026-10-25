package enum LogFileError: Error, CustomStringConvertible {
  case cannotOpen(String, String)

  package var description: String {
    switch self {
    case .cannotOpen(let path, let reason): "cannot open \(path): \(reason)"
    }
  }
}
