import Foundation
import Testing
import TylerCore

@testable import TylerProtocol

/// Socket paths are limited to ~104 bytes on macOS, and $TMPDIR is already long, so use /tmp.
func makeTempSocketPath() -> String {
  "/tmp/tyler-\(UUID().uuidString.prefix(8)).sock"
}

@Suite("UnixSocket")
struct UnixSocketTests {
  @Test func rejectsPathsThatAreTooLong() {
    let path = "/tmp/" + String(repeating: "a", count: 200)
    #expect(throws: UnixSocket.Failure.pathTooLong) {
      try UnixSocket.openListener(path: path)
    }
  }

  @Test func connectingToMissingSocketFails() {
    #expect(throws: (any Error).self) {
      try UnixSocket.openClient(path: makeTempSocketPath())
    }
  }

  /// macOS refuses a connection at once when the backlog is full, and `tyler` would report that
  /// as tylerd not running. A burst of commands (a held hotkey, the concurrent-clients test on a
  /// busy machine) must queue instead, even while nothing is accepted.
  @Test func queuesABurstOfConnectionsWithoutAccepting() throws {
    let path = makeTempSocketPath()
    defer { unlink(path) }
    let listener = try UnixSocket.openListener(path: path)
    defer { close(listener) }

    var clients: [Int32] = []
    defer {
      for client in clients { close(client) }
    }
    for _ in 0..<64 {
      clients.append(try UnixSocket.openClient(path: path))
    }
  }

  @Test func sendsALineBetweenListenerAndClient() throws {
    let path = makeTempSocketPath()
    defer { unlink(path) }
    let listener = try UnixSocket.openListener(path: path)
    defer { close(listener) }

    let client = try UnixSocket.openClient(path: path)
    defer { close(client) }
    let server = accept(listener, nil, nil)
    #expect(server >= 0)
    defer { close(server) }

    try UnixSocket.writeAll(fd: client, data: Data("hello\nignored".utf8))
    let line = UnixSocket.readLine(fd: server)
    #expect(line == Data("hello".utf8))
  }

  @Test func returnsPartialDataWhenPeerClosesWithoutNewline() throws {
    let path = makeTempSocketPath()
    defer { unlink(path) }
    let listener = try UnixSocket.openListener(path: path)
    defer { close(listener) }

    let client = try UnixSocket.openClient(path: path)
    let server = accept(listener, nil, nil)
    defer { close(server) }

    try UnixSocket.writeAll(fd: client, data: Data("partial".utf8))
    close(client)
    #expect(UnixSocket.readLine(fd: server) == Data("partial".utf8))
  }

  @Test func returnsNilWhenPeerClosesWithoutSendingAnything() throws {
    let path = makeTempSocketPath()
    defer { unlink(path) }
    let listener = try UnixSocket.openListener(path: path)
    defer { close(listener) }

    let client = try UnixSocket.openClient(path: path)
    let server = accept(listener, nil, nil)
    defer { close(server) }

    close(client)
    #expect(UnixSocket.readLine(fd: server) == nil)
  }

  @Test func givesUpOnOversizedLines() throws {
    let path = makeTempSocketPath()
    defer { unlink(path) }
    let listener = try UnixSocket.openListener(path: path)
    defer { close(listener) }

    let client = try UnixSocket.openClient(path: path)
    let server = accept(listener, nil, nil)
    defer { close(server) }

    // Keep the payload below the socket buffer (~8 KB): this thread both writes and reads,
    // so a larger write would block forever waiting for a reader.
    try UnixSocket.writeAll(fd: client, data: Data(repeating: 0x41, count: 3_000))
    #expect(UnixSocket.readLine(fd: server, maxBytes: 1_000) == nil)
    close(client)
  }
}
