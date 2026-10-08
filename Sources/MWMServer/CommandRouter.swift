import MWMCore

/// Maps a decoded `Request` to a `Response`. This is the seam where the WindowManager
/// plugs in from M2 onwards; for now only `ping` exists.
public struct CommandRouter: Sendable {
  public init() {}

  public func handle(_ request: Request) -> Response {
    switch request {
    case .ping:
      return .pong
    }
  }
}
