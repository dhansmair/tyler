import TylerProtocol

/// A parsed command line: what to do, and how to show the answer.
package struct Invocation: Equatable, Sendable {
  package enum Action: Equatable, Sendable {
    /// Send one request to the running server.
    case send(Request)
    /// Start, stop or inspect the server process.
    case daemon(DaemonCommand)
    /// Open the config file: in this terminal, or through tylerd (`ConfigEditing`).
    case editConfig
    /// Print the client's version (`--version`).
    case printVersion
  }

  package var action: Action
  package var format: OutputFormat

  package init(request: Request, format: OutputFormat = .text) {
    self.init(action: .send(request), format: format)
  }

  package init(action: Action, format: OutputFormat = .text) {
    self.action = action
    self.format = format
  }
}
