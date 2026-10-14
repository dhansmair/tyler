import Foundation

package enum SavedStateError: Error, Equatable, Sendable, CustomStringConvertible {
  case unwritable(path: String, reason: String)
  case unreadable(path: String, reason: String)
  case unknownVersion(path: String, version: Int)
  case stale(path: String, writtenAt: Date)

  package var description: String {
    switch self {
    case .unwritable(let path, let reason): "cannot write \(path): \(reason)"
    case .unreadable(let path, let reason): "cannot read \(path): \(reason)"
    case .unknownVersion(let path, let version):
      "\(path) has format version \(version), but this tylerd reads versions "
        + "\(SavedState.readableVersions.lowerBound) to \(SavedState.readableVersions.upperBound)"
    case .stale(let path, let writtenAt):
      "\(path) was left behind at \(writtenAt.formatted(.iso8601)), too long ago to hand over"
    }
  }
}
