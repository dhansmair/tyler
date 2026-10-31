import TylerCore
import TylerProtocol

/// What `tyler status` reports.
extension WindowManager {
  /// Whether tiling is running, for `tyler status`.
  package var tilingStatus: ServerStatus.Tiling {
    guard state == .running else { return .waitingForPermission }
    return tilingEnabled ? .on : .off
  }

  /// The event listeners in place, for `tyler status`.
  package var inputListeners: [InputListener] { pointer?.listeners ?? [] }
}
