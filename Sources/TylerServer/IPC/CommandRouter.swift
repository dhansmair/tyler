import TylerCore
import TylerProtocol

/// Maps a decoded `Request` to a `Response`. `ping`, `status` and `configEdit` are answered here;
/// everything else is forwarded to the main-actor `WindowManager`.
package struct CommandRouter: Sendable {
  private let manager: WindowManager?
  /// The server's process facts; `status` fills in the tiling state from the manager.
  private let status: ServerStatus?
  /// Opening an editor is tylerd's own: TylerServer can't reach the platform code that does it.
  private let openConfig: (@MainActor @Sendable () -> Response)?

  /// `manager` is `nil` only in tests that exercise the socket layer alone; window commands
  /// then answer with an error.
  package init(
    manager: WindowManager? = nil, status: ServerStatus? = nil,
    openConfig: (@MainActor @Sendable () -> Response)? = nil
  ) {
    self.manager = manager
    self.status = status
    self.openConfig = openConfig
  }

  /// From a socket thread. `ping` is answered there, so it works while the main actor waits on
  /// an app that is slow to answer.
  package func handle(_ request: Request) async -> Response {
    if case .ping = request { return .pong }
    return await MainActor.run { respond(to: request) }
  }

  /// From the main actor, as the menu bar items send them.
  @MainActor
  package func respond(to request: Request) -> Response {
    switch request {
    case .ping:
      return .pong
    case .status:
      guard var status else { return .error("status is not available") }
      if let manager {
        status.tiling = manager.tilingStatus
        status.configChanges = manager.configChanges
        status.access = manager.access
      }
      return .status(status)
    case .configEdit:
      return openConfig?() ?? .error("opening the config file is not available")
    default:
      guard let manager else { return .error("window management is not available") }
      return manager.handle(request)
    }
  }
}
