import CoreGraphics
import MWMCore

@testable import MWMServer

func makeWindow(
  id: UInt32,
  title: String = "",
  frame: CGRect = CGRect(x: 100, y: 100, width: 400, height: 300),
  kind: WindowKind = .standard,
  isMinimized: Bool = false,
  isFullscreen: Bool = false,
  isFocused: Bool = false
) -> WindowInfo {
  WindowInfo(
    id: WindowID(id),
    processID: 500,
    appName: "App",
    title: title,
    frame: frame,
    kind: kind,
    isMinimized: isMinimized,
    isFullscreen: isFullscreen,
    isFocused: isFocused
  )
}

/// A scriptable `WindowBackend`: tests push events into it and read back what was asked of it.
/// By default it behaves like an obedient app: a successful `setFrame` moves the window to
/// exactly the requested frame and reports that back as an `updated` event.
@MainActor
final class FakeBackend: WindowBackend {
  let events: AsyncStream<WindowEvent>
  private let continuation: AsyncStream<WindowEvent>.Continuation

  var windows: [WindowInfo]
  private(set) var startCount = 0
  private(set) var stopCount = 0

  /// Every successful `setFrame`, in order.
  private(set) var moves: [Placement] = []
  /// Every `focus` call, in order, including ones that failed.
  private(set) var focusCalls: [WindowID] = []
  /// Windows whose `setFrame` throws.
  var failingMoves: Set<WindowID> = []
  /// Windows whose `focus` throws.
  var failingFocus: Set<WindowID> = []

  init(windows: [WindowInfo] = []) {
    self.windows = windows
    (events, continuation) = AsyncStream.makeStream(of: WindowEvent.self)
  }

  func start() { startCount += 1 }
  func stop() { stopCount += 1 }
  func snapshot() -> [WindowInfo] { windows }

  func setFrame(_ frame: CGRect, of windowID: WindowID) throws(BackendError) {
    if failingMoves.contains(windowID) { throw .refused("fake refusal") }
    guard let index = windows.firstIndex(where: { $0.id == windowID }) else {
      throw .windowGone(windowID)
    }
    moves.append(Placement(id: windowID, frame: frame))
    windows[index].frame = frame
    continuation.yield(.updated(windows[index]))
  }

  func focus(_ windowID: WindowID) throws(BackendError) {
    focusCalls.append(windowID)
    if failingFocus.contains(windowID) { throw .refused("fake refusal") }
  }

  func send(_ event: WindowEvent) { continuation.yield(event) }
  func finish() { continuation.finish() }

  func clearRecordedCalls() {
    moves = []
    focusCalls = []
  }
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

  /// A second display to the right of `main`.
  static let secondary = DisplayInfo(
    id: 2,
    frame: CGRect(x: 1800, y: 0, width: 1920, height: 1080),
    visibleFrame: CGRect(x: 1800, y: 0, width: 1920, height: 1080)
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
