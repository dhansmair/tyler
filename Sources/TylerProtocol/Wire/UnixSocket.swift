import Foundation
import TylerCore

/// Thin POSIX helpers for blocking, stream-oriented Unix domain sockets.
package enum UnixSocket {
  package enum Failure: Error, Equatable {
    case pathTooLong
    case syscall(String, Int32)
  }

  /// Binds and listens on `path`. The caller owns the returned descriptor. On macOS a client
  /// that connects while the backlog is full is refused at once rather than made to wait, so
  /// the default is the system maximum: a burst of commands queues instead of failing.
  package static func openListener(path: String, backlog: Int32 = SOMAXCONN) throws -> Int32 {
    var addr = try address(for: path)
    let fd = try makeSocket()
    try check(withSockaddr(&addr) { bind(fd, $0, $1) }, "bind", closing: fd)
    try check(Darwin.listen(fd, backlog), "listen", closing: fd)
    return fd
  }

  /// Connects to a listening socket at `path`. The caller owns the returned descriptor.
  package static func openClient(path: String) throws -> Int32 {
    var addr = try address(for: path)
    let fd = try makeSocket()
    try check(withSockaddr(&addr) { Darwin.connect(fd, $0, $1) }, "connect", closing: fd)
    return fd
  }

  /// Reads up to the first `\n` (not included). Returns the bytes read so far if the peer
  /// closes without a newline, and `nil` if nothing was read, on error or timeout, or if
  /// more than `maxBytes` arrive without a newline.
  package static func readLine(fd: Int32, maxBytes: Int = 1 << 20) -> Data? {
    guard case .line(let line) = readLineOrHangUp(fd: fd, maxBytes: maxBytes) else { return nil }
    return line
  }

  /// `readLine`, telling a peer that closed without sending anything apart from a failed read.
  package static func readLineOrHangUp(fd: Int32, maxBytes: Int = 1 << 20) -> LineRead {
    var buffer = Data()
    var chunk = [UInt8](repeating: 0, count: 4096)
    while true {
      let count = chunk.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
      if count < 0 {
        if errno == EINTR { continue }
        return .failed
      }
      if count == 0 { return buffer.isEmpty ? .hungUp : .line(buffer) }
      buffer.append(contentsOf: chunk[0..<count])
      if let newline = buffer.firstIndex(of: Wire.terminator) {
        return .line(Data(buffer[buffer.startIndex..<newline]))
      }
      if buffer.count > maxBytes { return .failed }
    }
  }

  package static func writeAll(fd: Int32, data: Data) throws {
    try data.withUnsafeBytes { raw in
      guard let base = raw.baseAddress else { return }
      var offset = 0
      while offset < raw.count {
        let written = write(fd, base + offset, raw.count - offset)
        if written < 0 {
          if errno == EINTR { continue }
          throw Failure.syscall("write", errno)
        }
        offset += written
      }
    }
  }

  package static func setNonBlocking(fd: Int32, _ enabled: Bool) {
    let flags = fcntl(fd, F_GETFL)
    _ = fcntl(fd, F_SETFL, enabled ? flags | O_NONBLOCK : flags & ~O_NONBLOCK)
  }

  package static func setReceiveTimeout(fd: Int32, seconds: Int) {
    var timeout = timeval(tv_sec: seconds, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
  }

  // MARK: - Private

  private static func makeSocket() throws -> Int32 {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { throw Failure.syscall("socket", errno) }
    // A peer that disappears should surface as a write error, not kill the process.
    var enabled: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size))
    return fd
  }

  /// Calls `body` with `addr` as the generic `sockaddr` that `bind` and `connect` take.
  private static func withSockaddr(
    _ addr: inout sockaddr_un, _ body: (UnsafePointer<sockaddr>, socklen_t) -> Int32
  ) -> Int32 {
    withUnsafePointer(to: &addr) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        body($0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
  }

  /// Throws the failed call's error, after closing `fd`, unless `result` is 0.
  private static func check(_ result: Int32, _ call: String, closing fd: Int32) throws {
    guard result != 0 else { return }
    let code = errno
    close(fd)
    throw Failure.syscall(call, code)
  }

  private static func address(for path: String) throws -> sockaddr_un {
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8)
    // Keep room for the terminating NUL.
    guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else {
      throw Failure.pathTooLong
    }
    withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: bytes) }
    addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    return addr
  }
}
