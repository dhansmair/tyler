import Foundation
import Testing

@testable import TylerRuntime

@Suite("LogFile")
struct LogFileTests {
  @Test func devNullIsDiscarded() throws {
    let null = open("/dev/null", O_WRONLY)
    try #require(null >= 0)
    defer { close(null) }
    #expect(LogFile.isDiscarded(null))
  }

  /// A number no test opens: closing one of its own could race with a parallel test reusing it.
  @Test func closedDescriptorIsDiscarded() {
    #expect(LogFile.isDiscarded(9_999))
  }

  /// A terminal is a character device too.
  @Test func otherCharacterDeviceIsKept() throws {
    let zero = open("/dev/zero", O_WRONLY)
    try #require(zero >= 0)
    defer { close(zero) }
    #expect(!LogFile.isDiscarded(zero))
  }

  @Test func pipeIsKept() throws {
    var ends: [Int32] = [0, 0]
    try #require(pipe(&ends) == 0)
    defer {
      close(ends[0])
      close(ends[1])
    }
    #expect(!LogFile.isDiscarded(ends[1]))
  }

  @Test func regularFileIsKept() throws {
    let path = NSTemporaryDirectory() + "tyler-log-file-\(UUID().uuidString).log"
    let file = open(path, O_WRONLY | O_CREAT, 0o644)
    try #require(file >= 0)
    defer {
      close(file)
      unlink(path)
    }
    #expect(!LogFile.isDiscarded(file))
  }

  @Test func thePreviousLogIsKeptBesideTheNewOne() throws {
    let path = NSTemporaryDirectory() + "tyler-log-file-\(UUID().uuidString).log"
    defer {
      unlink(path)
      unlink(path + ".1")
    }
    try "older\n".write(toFile: path + ".1", atomically: false, encoding: .utf8)
    try "previous\n".write(toFile: path, atomically: false, encoding: .utf8)
    try LogFile.keepPrevious(at: path)
    #expect(try String(contentsOfFile: path + ".1", encoding: .utf8) == "previous\n")
    #expect(!FileManager.default.fileExists(atPath: path))
  }

  @Test func withoutALogNothingIsKept() throws {
    let path = NSTemporaryDirectory() + "tyler-log-file-\(UUID().uuidString).log"
    try LogFile.keepPrevious(at: path)
    #expect(!FileManager.default.fileExists(atPath: path + ".1"))
  }
}
