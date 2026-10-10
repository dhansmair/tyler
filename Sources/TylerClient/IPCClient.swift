import Foundation
import TylerCore

public enum IPCClientError: Error, Equatable {
  case serverNotRunning(String)
  case badReply
}

/// Sends a single `Request` to `tylerd` and waits for its `Response`.
public struct IPCClient: Sendable {
  public let path: String
  public let timeoutSeconds: Int

  public init(path: String = Paths.socketPath(), timeoutSeconds: Int = 5) {
    self.path = path
    self.timeoutSeconds = timeoutSeconds
  }

  public func send(_ request: Request) throws -> Response {
    let fd: Int32
    do {
      fd = try UnixSocket.openClient(path: path)
    } catch {
      throw IPCClientError.serverNotRunning(path)
    }
    defer { close(fd) }
    UnixSocket.setReceiveTimeout(fd: fd, seconds: timeoutSeconds)

    try UnixSocket.writeAll(fd: fd, data: try Wire.encode(request))
    guard let line = UnixSocket.readLine(fd: fd) else {
      throw IPCClientError.badReply
    }
    do {
      return try Wire.decode(Response.self, from: line)
    } catch {
      throw IPCClientError.badReply
    }
  }
}
