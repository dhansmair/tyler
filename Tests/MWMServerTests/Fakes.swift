import CoreGraphics
import MWMCore

@testable import MWMServer

func makeWindow(
  id: UInt32,
  title: String = "",
  frame: CGRect = CGRect(x: 100, y: 100, width: 400, height: 300),
  kind: WindowKind = .standard,
  isFocused: Bool = false
) -> WindowInfo {
  WindowInfo(
    id: WindowID(id),
    processID: 500,
    appName: "App",
    title: title,
    frame: frame,
    kind: kind,
    isFocused: isFocused
  )
}

/// A scriptable `WindowBackend`: tests push events into it and read back what was called.
@MainActor
final class FakeBackend: WindowBackend {
  let events: AsyncStream<WindowEvent>
  private let continuation: AsyncStream<WindowEvent>.Continuation

  var windows: [WindowInfo]
  private(set) var startCount = 0
  private(set) var stopCount = 0

  init(windows: [WindowInfo] = []) {
    self.windows = windows
    (events, continuation) = AsyncStream.makeStream(of: WindowEvent.self)
  }

  func start() { startCount += 1 }
  func stop() { stopCount += 1 }
  func snapshot() -> [WindowInfo] { windows }

  func send(_ event: WindowEvent) { continuation.yield(event) }
  func finish() { continuation.finish() }
}

@MainActor
final class FakeDisplays: DisplayProvider {
  var displays: [DisplayInfo]

  init(displays: [DisplayInfo] = [FakeDisplays.main]) {
    self.displays = displays
  }

  static let main = DisplayInfo(
    id: 1,
    frame: CGRect(x: 0, y: 0, width: 1800, height: 1169),
    visibleFrame: CGRect(x: 55, y: 38, width: 1745, height: 1131)
  )
}

@MainActor
final class FakeGate: AccessibilityGate {
  var isTrusted: Bool
  private(set) var promptCount = 0

  init(isTrusted: Bool) {
    self.isTrusted = isTrusted
  }

  func prompt() { promptCount += 1 }
}
