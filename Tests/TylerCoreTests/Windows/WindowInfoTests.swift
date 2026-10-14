import CoreGraphics
import Foundation
import Testing

@testable import TylerCore

@Suite("WindowInfo")
struct WindowInfoTests {
  private func makeWindow(
    kind: WindowKind = .standard,
    isMinimized: Bool = false,
    isFullscreen: Bool = false
  ) -> WindowInfo {
    WindowInfo(
      id: WindowID(42),
      processID: 100,
      appName: "TextEdit",
      frame: CGRect(x: 10, y: 20, width: 300, height: 200),
      kind: kind,
      isMinimized: isMinimized,
      isFullscreen: isFullscreen
    )
  }

  @Test func roundTripsThroughJSON() throws {
    var window = makeWindow()
    window.bundleID = "com.apple.TextEdit"
    window.title = "Untitled — Edited"
    window.displayID = 7
    let data = try JSONEncoder().encode(window)
    #expect(try JSONDecoder().decode(WindowInfo.self, from: data) == window)
  }

  @Test func windowIDEncodesAsABareNumber() throws {
    let data = try JSONEncoder().encode(WindowID(42))
    #expect(String(data: data, encoding: .utf8) == "42")
  }

  @Test func windowsAreOrderedByID() {
    #expect(
      [WindowID(3), WindowID(1), WindowID(2)].sorted() == [WindowID(1), WindowID(2), WindowID(3)])
  }

  @Test func onlyOnScreenStandardWindowsAreTileable() {
    #expect(makeWindow().isTileable)
    #expect(!makeWindow(kind: .dialog).isTileable)
    #expect(!makeWindow(kind: .floating).isTileable)
    #expect(!makeWindow(kind: .other).isTileable)
    #expect(!makeWindow(isMinimized: true).isTileable)
    #expect(!makeWindow(isFullscreen: true).isTileable)
  }
}
