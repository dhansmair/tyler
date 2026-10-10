import CoreGraphics
import Foundation
import TylerCore

@testable import TylerServer

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
  /// Every successful `setPosition` (animation steps), in order.
  private(set) var nudges: [(id: WindowID, origin: CGPoint)] = []
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

  /// Moves the window but, like the real backend, reports nothing back.
  func setPosition(_ origin: CGPoint, of windowID: WindowID) throws(BackendError) {
    if failingMoves.contains(windowID) { throw .refused("fake refusal") }
    guard let index = windows.firstIndex(where: { $0.id == windowID }) else {
      throw .windowGone(windowID)
    }
    nudges.append((windowID, origin))
    windows[index].frame.origin = origin
  }

  func focus(_ windowID: WindowID) throws(BackendError) {
    focusCalls.append(windowID)
    if failingFocus.contains(windowID) { throw .refused("fake refusal") }
  }

  func send(_ event: WindowEvent) { continuation.yield(event) }
  func finish() { continuation.finish() }

  func clearRecordedCalls() {
    moves = []
    nudges = []
    focusCalls = []
  }
}

/// A scriptable `PointerInput`: tests hold the button down and release it.
@MainActor
final class FakePointer: PointerInput {
  let events: AsyncStream<PointerEvent>
  private let continuation: AsyncStream<PointerEvent>.Continuation
  var isPrimaryButtonDown = false
  private(set) var startCount = 0
  private(set) var stopCount = 0

  init() {
    (events, continuation) = AsyncStream.makeStream(of: PointerEvent.self)
  }

  func start() { startCount += 1 }
  func stop() { stopCount += 1 }

  /// Lets go of the button, as the user would at the end of a drag.
  func release(at location: CGPoint = .zero) {
    isPrimaryButtonDown = false
    continuation.yield(.primaryButtonReleased(location: location))
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

/// A clock that only moves when the test calls `advance(by:)`, so animations can be stepped
/// (or held mid-way) without sleeping. It is `@unchecked Sendable` because all mutable state is
/// guarded by `lock`.
final class TestClock: Clock, @unchecked Sendable {
  struct Instant: InstantProtocol {
    var offset: Duration

    func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
    func duration(to other: Instant) -> Duration { other.offset - offset }
    static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
  }

  private struct Sleeper {
    let id: UUID
    let deadline: Instant
    let continuation: CheckedContinuation<Void, any Error>
  }

  private let lock = NSLock()
  private var current = Instant(offset: .zero)
  private var sleepers: [Sleeper] = []

  var now: Instant { lock.withLock { current } }
  var minimumResolution: Duration { .zero }

  /// Whether something is waiting for the clock to advance.
  var hasSleepers: Bool { lock.withLock { !sleepers.isEmpty } }

  func sleep(until deadline: Instant, tolerance: Duration?) async throws {
    let id = UUID()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        enqueue(Sleeper(id: id, deadline: deadline, continuation: continuation))
      }
    } onCancel: {
      let sleeper = lock.withLock { () -> Sleeper? in
        guard let index = sleepers.firstIndex(where: { $0.id == id }) else { return nil }
        return sleepers.remove(at: index)
      }
      sleeper?.continuation.resume(throwing: CancellationError())
    }
  }

  /// Parks a sleeper until its deadline, or resumes it at once if it is due or cancelled. The
  /// cancellation check happens under the lock so it can't race with the cancellation handler.
  private func enqueue(_ sleeper: Sleeper) {
    enum Outcome { case due, cancelled, waiting }
    let outcome = lock.withLock { () -> Outcome in
      if Task.isCancelled { return .cancelled }
      if sleeper.deadline <= current { return .due }
      sleepers.append(sleeper)
      return .waiting
    }
    switch outcome {
    case .due: sleeper.continuation.resume()
    case .cancelled: sleeper.continuation.resume(throwing: CancellationError())
    case .waiting: break
    }
  }

  func advance(by duration: Duration) {
    let due = lock.withLock { () -> [Sleeper] in
      current = current.advanced(by: duration)
      let due = sleepers.filter { $0.deadline <= current }
      sleepers.removeAll { $0.deadline <= current }
      return due
    }
    for sleeper in due { sleeper.continuation.resume() }
  }
}

/// A config file whose contents the test can change between reloads. `@unchecked Sendable`
/// because `contents` is only touched under `lock`.
final class FakeConfigFile: @unchecked Sendable {
  enum Contents {
    case missing
    case config(Config)
    case broken(ConfigError)
  }

  static let path = "/test/tyler.toml"

  private let lock = NSLock()
  private var contents: Contents

  init(_ contents: Contents = .missing) {
    self.contents = contents
  }

  func write(_ contents: Contents) {
    lock.withLock { self.contents = contents }
  }

  var source: ConfigSource {
    ConfigSource(path: Self.path) { () throws(ConfigError) -> Config? in
      switch self.lock.withLock({ self.contents }) {
      case .missing: return nil
      case .config(let config): return config
      case .broken(let error): throw error
      }
    }
  }
}

/// Records every state the manager shows.
@MainActor
final class FakeIndicator: Indicator {
  private(set) var shown: [IndicatorState] = []

  func show(_ state: IndicatorState) { shown.append(state) }
}
