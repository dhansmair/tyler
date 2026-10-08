import Foundation
import MWMClient
import MWMCore
import Testing

@testable import MWMServer

private func makeSocketPath() -> String {
  "/tmp/mwm-\(UUID().uuidString.prefix(8)).sock"
}

/// `@unchecked Sendable`: `storage` is only touched while holding `lock`.
private final class ResultBox: @unchecked Sendable {
  private let lock = NSLock()
  private var storage: [Result<Response, any Error>] = []

  func append(_ result: Result<Response, any Error>) {
    lock.lock()
    storage.append(result)
    lock.unlock()
  }

  var values: [Result<Response, any Error>] {
    lock.lock()
    defer { lock.unlock() }
    return storage
  }
}

/// Sends raw bytes and returns the server's single-line reply.
private func rawExchange(path: String, send payload: String) throws -> String? {
  let fd = try UnixSocket.openClient(path: path)
  defer { close(fd) }
  UnixSocket.setReceiveTimeout(fd: fd, seconds: 5)
  try UnixSocket.writeAll(fd: fd, data: Data(payload.utf8))
  return UnixSocket.readLine(fd: fd).flatMap { String(data: $0, encoding: .utf8) }
}

@Suite("IPCServer", .serialized)
struct IPCServerTests {
  @Test func clientAndServerRoundTripPing() throws {
    let path = makeSocketPath()
    let server = IPCServer(path: path) { await CommandRouter().handle($0) }
    try server.start()
    defer { server.stop() }

    let response = try IPCClient(path: path).send(.ping)
    #expect(response == .pong)
  }

  @Test func malformedRequestGetsAnErrorResponse() throws {
    let path = makeSocketPath()
    let server = IPCServer(path: path) { await CommandRouter().handle($0) }
    try server.start()
    defer { server.stop() }

    let reply = try rawExchange(path: path, send: "this is not json\n")
    let response = try Wire.decode(Response.self, from: Data(try #require(reply).utf8))
    #expect(response == .error("malformed request"))
  }

  @Test func serverKeepsServingAfterABadClient() throws {
    let path = makeSocketPath()
    let server = IPCServer(path: path) { await CommandRouter().handle($0) }
    try server.start()
    defer { server.stop() }

    // Connects and hangs up without sending anything.
    close(try UnixSocket.openClient(path: path))

    #expect(try IPCClient(path: path).send(.ping) == .pong)
  }

  @Test func handlesConcurrentClients() throws {
    let path = makeSocketPath()
    let server = IPCServer(path: path) { await CommandRouter().handle($0) }
    try server.start()
    defer { server.stop() }

    // Plain threads, not Swift concurrency: the client calls block in read(). A task-group
    // version of this test failed ~80% of runs with a 10s timeout (.badReply); real threads
    // pass reliably. Suspected cause is blocking calls on the cooperative pool, not verified.
    let client = IPCClient(path: path)
    let results = ResultBox()
    let group = DispatchGroup()
    for _ in 0..<20 {
      group.enter()
      Thread {
        results.append(Result { try client.send(.ping) })
        group.leave()
      }.start()
    }
    #expect(group.wait(timeout: .now() + 10) == .success)

    let all = results.values
    #expect(all.count == 20)
    #expect(all.allSatisfy { (try? $0.get()) == .pong })
  }

  @Test func secondServerOnTheSamePathIsRefused() throws {
    let path = makeSocketPath()
    let first = IPCServer(path: path) { await CommandRouter().handle($0) }
    try first.start()
    defer { first.stop() }

    let second = IPCServer(path: path) { await CommandRouter().handle($0) }
    #expect(throws: IPCServer.Failure.alreadyRunning(path)) {
      try second.start()
    }
    // The refused server must not have clobbered the live one.
    #expect(try IPCClient(path: path).send(.ping) == .pong)
  }

  @Test func staleSocketFileIsReplaced() throws {
    let path = makeSocketPath()
    // Simulate a crashed server: a socket file with nobody listening.
    let stale = try UnixSocket.openListener(path: path)
    close(stale)
    #expect(FileManager.default.fileExists(atPath: path))

    let server = IPCServer(path: path) { await CommandRouter().handle($0) }
    try server.start()
    defer { server.stop() }

    #expect(try IPCClient(path: path).send(.ping) == .pong)
  }

  @Test @MainActor func listWorksEndToEndOverTheSocket() async throws {
    let backend = FakeBackend(windows: [makeWindow(id: 11, title: "hello", isFocused: true)])
    let manager = WindowManager(
      backend: backend,
      displays: FakeDisplays(),
      gate: FakeGate(isTrusted: true)
    )
    manager.startIfPermitted()
    let router = CommandRouter(manager: manager)

    let path = makeSocketPath()
    let server = IPCServer(path: path) { [router] request in await router.handle(request) }
    try server.start()
    defer { server.stop() }

    // The client blocks in read(), so it runs on a plain thread: the main actor has to stay free
    // to answer, and this test function is itself running on it.
    let response = await withCheckedContinuation { continuation in
      Thread {
        continuation.resume(returning: Result { try IPCClient(path: path).send(.list) })
      }.start()
    }
    guard case .windows(let windows) = try response.get() else {
      Issue.record("expected a window list")
      return
    }
    #expect(windows.map(\.id.rawValue) == [11])
    #expect(windows.first?.title == "hello")
    #expect(windows.first?.isFocused == true)
    #expect(windows.first?.displayID == 1)
  }

  @Test @MainActor func anActionCommandWorksEndToEndOverTheSocket() async throws {
    let backend = FakeBackend(windows: [
      makeWindow(id: 1, frame: CGRect(x: 100, y: 100, width: 300, height: 200)),
      makeWindow(id: 2, frame: CGRect(x: 500, y: 100, width: 300, height: 200)),
    ])
    let manager = WindowManager(
      backend: backend, displays: FakeDisplays(), gate: FakeGate(isTrusted: true))
    manager.startIfPermitted()
    backend.clearRecordedCalls()
    let router = CommandRouter(manager: manager)

    let path = makeSocketPath()
    let server = IPCServer(path: path) { [router] request in await router.handle(request) }
    try server.start()
    defer { server.stop() }

    let response = await withCheckedContinuation { continuation in
      Thread {
        continuation.resume(returning: Result { try IPCClient(path: path).send(.layout(.next)) })
      }.start()
    }
    #expect(try response.get() == .message("layout full"))
    // The command reached the manager and moved the windows through the backend.
    #expect(Set(backend.moves.map(\.id.rawValue)) == [1, 2])
    #expect(backend.moves.allSatisfy { $0.frame == FakeDisplays.main.visibleFrame })
  }

  @Test func stopRemovesTheSocketFile() throws {
    let path = makeSocketPath()
    let server = IPCServer(path: path) { await CommandRouter().handle($0) }
    try server.start()
    #expect(FileManager.default.fileExists(atPath: path))

    server.stop()
    #expect(!FileManager.default.fileExists(atPath: path))
    server.stop()  // idempotent
  }

  @Test func clientReportsMissingServer() {
    let path = makeSocketPath()
    #expect(throws: IPCClientError.serverNotRunning(path)) {
      try IPCClient(path: path).send(.ping)
    }
  }
}
