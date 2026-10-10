import TylerCore

/// Maps a decoded `Request` to a `Response`. `ping` is answered directly; everything else is
/// forwarded to the main-actor `WindowManager`.
public struct CommandRouter: Sendable {
  private let manager: WindowManager?

  /// `manager` is `nil` only in tests that exercise the socket layer alone; window commands
  /// then answer with an error.
  public init(manager: WindowManager? = nil) {
    self.manager = manager
  }

  public func handle(_ request: Request) async -> Response {
    guard request != .ping else { return .pong }
    guard let manager else { return .error("window management is not available") }
    return await manager.handle(request)
  }
}
