import TylerCore
import TylerProtocol

/// What `tyler status` reports, besides `access`.
extension WindowManager {
  package var tilingStatus: ServerStatus.Tiling {
    guard state == .running else { return .waitingForPermission }
    return tilingEnabled ? .on : .off
  }

  package var inputListeners: [InputListener] { pointer?.listeners ?? [] }
}
