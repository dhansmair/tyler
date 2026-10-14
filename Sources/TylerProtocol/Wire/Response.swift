import TylerCore

/// The server's reply to a `Request`.
package enum Response: Codable, Equatable, Sendable {
  case pong
  /// The command succeeded and there is nothing to report.
  case ok
  /// The command succeeded; the text is for the user.
  case message(String)
  case windows([WindowInfo])
  case status(ServerStatus)
  /// The answer to `debugAt`.
  case pointer(PointerDiagnosis)
  /// The answer to `debugWindows`.
  case drift(WindowDrift)
  case error(String)
}
