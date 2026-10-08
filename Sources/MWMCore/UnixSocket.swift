import Foundation

/// Thin POSIX helpers for blocking, stream-oriented Unix domain sockets.
public enum UnixSocket {
  public enum Failure: Error, Equatable {
    case pathTooLong
    case syscall(String, Int32)
  }

  /// Binds and listens on `path`. The caller owns the returned descriptor.
  public static func openListener(path: String, backlog: Int32 = 16) throws -> Int32 {
    var addr = try address(for: path)
    let fd = try makeSocket()
    let bound = withUnsafePointer(to: &addr) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    guard bound == 0 else {
      let code = errno
      close(fd)
      throw Failure.syscall("bind", code)
    }
    guard Darwin.listen(fd, backlog) == 0 else {
      let code = errno
      close(fd)
      throw Failure.syscall("listen", code)
    }
    return fd
  }

  /// Connects to a listening socket at `path`. The caller owns the returned descriptor.
  public static func openClient(path: String) throws -> Int32 {
    var addr = try address(for: path)
    let fd = try makeSocket()
    let connected = withUnsafePointer(to: &addr) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    guard connected == 0 else {
      let code = errno
      close(fd)
      throw Failure.syscall("connect", code)
    }
    return fd
  }

  /// Reads up to the first `\n` (not included). Returns the bytes read so far if the peer
  /// closes without a newline, and `nil` if nothing was read, on error or timeout, or if
  /// more than `maxBytes` arrive without a newline.
  public static func readLine(fd: Int32, maxBytes: Int = 1 << 20) -> Data? {
    var buffer = Data()
    var chunk = [UInt8](repeating: 0, count: 4096)
    while true {
      let count = chunk.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
      if count < 0 {
        if errno == EINTR { continue }
        return nil
      }
      if count == 0 { return buffer.isEmpty ? nil : buffer }
      buffer.append(contentsOf: chunk[0..<count])
      if let newline = buffer.firstIndex(of: 0x0A) {
        return Data(buffer[buffer.startIndex..<newline])
      }
      if buffer.count > maxBytes { return nil }
    }
  }

  public static func writeAll(fd: Int32, data: Data) throws {
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

  public static func setNonBlocking(fd: Int32, _ enabled: Bool) {
    let flags = fcntl(fd, F_GETFL)
    _ = fcntl(fd, F_SETFL, enabled ? flags | O_NONBLOCK : flags & ~O_NONBLOCK)
  }

  public static func setReceiveTimeout(fd: Int32, seconds: Int) {
    var timeout = timeval(tv_sec: seconds, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
  }

  // MARK: - Private

  private static func makeSocket() throws -> Int32 {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { throw Failure.syscall("socket", errno) }
    // A peer that disappears should surface as a write error, not kill the process.
    var on: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    return fd
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
