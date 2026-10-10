import TylerCore

/// Maps a decoded `Request` to a `Response`. `ping` and `status` are answered here; everything
/// else is forwarded to the main-actor `WindowManager`.
public struct CommandRouter: Sendable {
  private let manager: WindowManager?
  /// The server's process facts; `status` fills in the tiling state from the manager.
  private let status: ServerStatus?

  /// `manager` is `nil` only in tests that exercise the socket layer alone; window commands
  /// then answer with an error.
  public init(manager: WindowManager? = nil, status: ServerStatus? = nil) {
    self.manager = manager
    self.status = status
  }

  public func handle(_ request: Request) async -> Response {
    switch request {
    case .ping:
      return .pong
    case .status:
      guard var status else { return .error("status is not available") }
      if let manager { status.tiling = await manager.tilingStatus }
      return .status(status)
    default:
      guard let manager else { return .error("window management is not available") }
      return await manager.handle(request)
    }
  }
}
