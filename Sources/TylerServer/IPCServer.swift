import Foundation
import OSLog
import TylerCore

/// Listens on a Unix socket and answers one newline-delimited JSON `Request` per connection.
///
/// Connections are served concurrently, so `handler` must be safe to call from any thread.
/// Once the WindowManager exists, the handler is responsible for hopping to the main actor.
///
/// `@unchecked Sendable`: all mutable state (`listenerFD`, `stopRequested`) is guarded by `lock`,
/// and everything else is immutable after `init`.
public final class IPCServer: @unchecked Sendable {
  public enum Failure: Error, Equatable {
    case alreadyRunning(String)
  }

  public typealias Handler = @Sendable (Request) async -> Response

  private let path: String
  private let handler: Handler
  private let lock = NSLock()
  private var listenerFD: Int32 = -1
  private var stopRequested = false
  private let acceptLoopFinished = DispatchSemaphore(value: 0)
  private let workers = DispatchQueue(label: "tyler.ipc.workers", attributes: .concurrent)
  private static let log = Logger(subsystem: "tyler", category: "ipc")

  public init(path: String, handler: @escaping Handler) {
    self.path = path
    self.handler = handler
  }

  /// Binds the socket and starts accepting connections on a background thread.
  /// Throws `Failure.alreadyRunning` if another server answers on `path`.
  public func start() throws {
    let directory = (path as NSString).deletingLastPathComponent
    if !directory.isEmpty {
      try FileManager.default.createDirectory(
        atPath: directory,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
      )
    }

    try removeStaleSocket()

    let fd = try UnixSocket.openListener(path: path)
    chmod(path, 0o600)
    UnixSocket.setNonBlocking(fd: fd, true)

    lock.lock()
    listenerFD = fd
    stopRequested = false
    lock.unlock()

    let thread = Thread { [weak self] in
      self?.acceptLoop(fd: fd)
      self?.acceptLoopFinished.signal()
    }
    thread.name = "tyler.ipc.accept"
    thread.start()
  }

  /// Stops accepting, closes the listener and removes the socket file. Safe to call twice.
  public func stop() {
    lock.lock()
    let fd = listenerFD
    listenerFD = -1
    stopRequested = true
    lock.unlock()
    guard fd >= 0 else { return }
    // The accept loop polls with a short timeout and exits once it sees `stopRequested`.
    // Wait for it so the descriptor is never closed underneath a poll/accept call.
    acceptLoopFinished.wait()
    close(fd)
    unlink(path)
  }

  // MARK: - Private

  /// Removes a leftover socket file, unless a live server is still behind it.
  private func removeStaleSocket() throws {
    guard FileManager.default.fileExists(atPath: path) else { return }
    let probe: Int32
    do {
      probe = try UnixSocket.openClient(path: path)
    } catch {
      // Nobody is listening, so the file is a leftover from a crashed server.
      unlink(path)
      return
    }
    close(probe)
    throw Failure.alreadyRunning(path)
  }

  private var isStopping: Bool {
    lock.lock()
    defer { lock.unlock() }
    return stopRequested
  }

  private func acceptLoop(fd: Int32) {
    while !isStopping {
      var pollfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
      let ready = poll(&pollfd, 1, 100)
      if ready <= 0 { continue }
      let client = accept(fd, nil, nil)
      if client < 0 { continue }
      UnixSocket.setNonBlocking(fd: client, false)
      UnixSocket.setReceiveTimeout(fd: client, seconds: 5)
      var enabled: Int32 = 1
      setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size))
      workers.async { [handler] in
        Self.serve(client: client, handler: handler)
      }
    }
  }

  /// The one bridge from a blocking GCD worker thread into async code. The worker waits, so the
  /// task is never detached from its caller's lifetime. This relies on the main thread being free
  /// to run the main actor while workers wait.
  private static func runBlocking(_ handler: @escaping Handler, on request: Request) -> Response {
    let box = ResponseBox()
    let done = DispatchSemaphore(value: 0)
    Task {
      box.set(await handler(request))
      done.signal()
    }
    done.wait()
    return box.value
  }

  private static func serve(client: Int32, handler: @escaping Handler) {
    defer { close(client) }
    let response: Response
    if let line = UnixSocket.readLine(fd: client) {
      do {
        response = runBlocking(handler, on: try Wire.decode(Request.self, from: line))
      } catch {
        response = .error(describeUndecodable(line))
      }
    } else {
      response = .error("no request received")
    }
    do {
      try UnixSocket.writeAll(fd: client, data: try Wire.encode(response))
    } catch {
      log.error("failed to send response: \(error.localizedDescription)")
    }
  }
}

/// Valid JSON that isn't a known request most likely comes from a newer `tyler` talking to a
/// `tylerd` that was started before a rebuild.
private func describeUndecodable(_ line: Data) -> String {
  do {
    _ = try JSONSerialization.jsonObject(with: line)
  } catch {
    return "malformed request"
  }
  return "unknown request: tylerd is probably older than tyler (run `tyler restart`)"
}

/// Hands a `Response` from a task back to the thread waiting on it.
///
/// `@unchecked Sendable`: `stored` is written once, before the semaphore is signalled, and read
/// only after the wait returns, and `lock` guards both accesses regardless.
private final class ResponseBox: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: Response = .error("no response")

  func set(_ response: Response) {
    lock.lock()
    stored = response
    lock.unlock()
  }

  var value: Response {
    lock.lock()
    defer { lock.unlock() }
    return stored
  }
}
