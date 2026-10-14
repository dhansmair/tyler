import CoreGraphics
import TylerCore

@testable import TylerServer

/// A scriptable `WindowSystem`: tests push events into it and read back what was asked of it.
/// By default it behaves like an obedient app: a successful `setFrame` moves the window to
/// exactly the requested frame and reports that back as an `updated` event.
@MainActor
package final class FakeWindowSystem: WindowSystem {
  package let events: AsyncStream<WindowEvent>
  private let continuation: AsyncStream<WindowEvent>.Continuation

  package var windows: [WindowInfo]
  package private(set) var startCount = 0
  package private(set) var stopCount = 0

  /// Every successful `setFrame`, in order.
  package private(set) var moves: [Placement] = []
  /// Every successful `setPosition` (animation steps), in order.
  package private(set) var nudges: [(id: WindowID, origin: CGPoint)] = []
  /// Every successful `setFrameStep` (steps of an animation that resizes), in order.
  package private(set) var frameSteps: [Placement] = []
  package private(set) var passingMoves: [Placement] = []
  /// Every `focus` call, in order, including ones that failed.
  package private(set) var focusCalls: [WindowID] = []
  /// Windows whose `setFrame` throws.
  package var failingMoves: Set<WindowID> = []
  /// Whether moves wait, as `MacWindowSystem`'s queues let them: `setPosition` and `setFrameStep` keep
  /// only the newest
  /// move of each window in `heldMoves` until `releaseHeldMoves()`, and a `setFrame` (or
  /// `setFrameInPassing`) first drops its window's held move and lands the others of its app, as
  /// an `AppConnection` does when it settles.
  package var holdsMoves = false
  package private(set) var heldMoves: [WindowID: CGRect] = [:]
  /// Runs at every move, so a test can let time pass while an app moves a window.
  package var onWrite: (() -> Void)?
  /// Windows whose `focus` throws.
  package var failingFocus: Set<WindowID> = []
  /// Every `close` call, in order, including ones that failed.
  package private(set) var closeCalls: [WindowID] = []
  /// Windows whose `close` throws.
  package var failingClose: Set<WindowID> = []
  /// How many times `unfocus` was called, including calls that failed.
  package private(set) var unfocusCount = 0
  /// Whether `unfocus` throws.
  package var isUnfocusFailing = false

  package init(windows: [WindowInfo] = []) {
    self.windows = windows
    (events, continuation) = AsyncStream.makeStream(of: WindowEvent.self)
  }

  package func start() { startCount += 1 }
  package func stop() { stopCount += 1 }
  package func snapshot() -> [WindowInfo] { windows }

  /// What `freshWindows` adds to the windows: those macOS has and the fake doesn't track, and the
  /// apps it couldn't observe.
  package var untracked: [WindowInfo] = []
  package var unattachedApps: [String] = []
  /// The window `freshWindows` reads as focused, whatever events were sent.
  package var freshFocus: WindowID?

  package func freshWindows() -> FreshWindows {
    FreshWindows(
      tracked: windows, untracked: untracked, unattachedApps: unattachedApps,
      focusedID: freshFocus)
  }

  package func setFrame(_ frame: CGRect, of windowID: WindowID) throws(WindowSystemError) {
    settle(windowID)
    let index = try movableIndex(of: windowID)
    moves.append(Placement(id: windowID, frame: frame))
    windows[index].frame = frame
    continuation.yield(.updated(windows[index]))
  }

  /// Like `setFrame`, but recorded in `passingMoves`: the app's own notifications report it.
  package func setFrameInPassing(_ frame: CGRect, of windowID: WindowID) throws(WindowSystemError) {
    settle(windowID)
    let index = try movableIndex(of: windowID)
    passingMoves.append(Placement(id: windowID, frame: frame))
    windows[index].frame = frame
    continuation.yield(.updated(windows[index]))
  }

  package func takeQueuedWrites() -> MotionCost.Queued { MotionCost.Queued() }

  /// Moves the window but, like the real window system, reports nothing back.
  package func setPosition(_ origin: CGPoint, of windowID: WindowID) throws(WindowSystemError) {
    let index = try movableIndex(of: windowID)
    nudges.append((windowID, origin))
    step(index, to: CGRect(origin: origin, size: windows[index].frame.size))
  }

  /// Moves and resizes the window but, like the real window system, reports nothing back.
  package func setFrameStep(_ frame: CGRect, of windowID: WindowID) throws(WindowSystemError) {
    let index = try movableIndex(of: windowID)
    frameSteps.append(Placement(id: windowID, frame: frame))
    step(index, to: frame)
  }

  private func step(_ index: Int, to frame: CGRect) {
    if holdsMoves {
      heldMoves[windows[index].id] = frame
    } else {
      windows[index].frame = frame
    }
  }

  /// Lands every held move: the queued steps an app gets to late.
  package func releaseHeldMoves() {
    for (windowID, frame) in heldMoves { land(frame, windowID) }
    heldMoves = [:]
  }

  private func settle(_ windowID: WindowID) {
    heldMoves[windowID] = nil
    let processID = windows.first { $0.id == windowID }?.processID
    for (heldID, frame) in heldMoves
    where windows.first(where: { $0.id == heldID })?.processID == processID {
      land(frame, heldID)
      heldMoves[heldID] = nil
    }
  }

  private func land(_ frame: CGRect, _ windowID: WindowID) {
    guard let index = windows.firstIndex(where: { $0.id == windowID }) else { return }
    windows[index].frame = frame
  }

  /// Where `windowID` is in `windows`, unless moving it fails: it is in `failingMoves` or gone.
  private func movableIndex(of windowID: WindowID) throws(WindowSystemError) -> Int {
    onWrite?()
    if failingMoves.contains(windowID) { throw .refused("fake refusal") }
    guard let index = windows.firstIndex(where: { $0.id == windowID }) else {
      throw .windowGone(windowID)
    }
    return index
  }

  package func focus(_ windowID: WindowID) throws(WindowSystemError) {
    focusCalls.append(windowID)
    if failingFocus.contains(windowID) { throw .refused("fake refusal") }
  }

  /// Closes the window as an app that asks nothing would: it is gone, and reported destroyed.
  package func close(_ windowID: WindowID) throws(WindowSystemError) {
    closeCalls.append(windowID)
    if failingClose.contains(windowID) { throw .refused("fake refusal") }
    guard let index = windows.firstIndex(where: { $0.id == windowID }) else {
      throw .windowGone(windowID)
    }
    windows.remove(at: index)
    continuation.yield(.destroyed(windowID))
  }

  package func unfocus() throws(WindowSystemError) {
    unfocusCount += 1
    if isUnfocusFailing { throw .refused("fake refusal") }
  }

  package func send(_ event: WindowEvent) { continuation.yield(event) }
  package func finish() { continuation.finish() }

  package func clearRecordedCalls() {
    moves = []
    nudges = []
    frameSteps = []
    passingMoves = []
    focusCalls = []
    closeCalls = []
    unfocusCount = 0
  }
}
