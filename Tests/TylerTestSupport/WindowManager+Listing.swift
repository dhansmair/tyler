import TylerCore
import TylerProtocol

@testable import TylerServer

extension WindowManager {
  /// What `tyler window list` would show; empty when it answers with an error.
  package var listed: [WindowInfo] {
    guard case .windows(let windows) = windows() else { return [] }
    return windows
  }

  /// Window id → 1-based slot in its workspace's list, for tiled windows.
  package var slots: [UInt32: Int] {
    Dictionary(
      uniqueKeysWithValues: listed.compactMap { window in
        window.slot.map { (window.id.rawValue, $0) }
      })
  }
}
