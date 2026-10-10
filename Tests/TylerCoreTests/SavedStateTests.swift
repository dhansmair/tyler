import CoreGraphics
import Foundation
import Testing

@testable import TylerCore

@Suite("Saved state")
struct SavedStateTests {
  /// Workspace 1: windows 1, 2, 3 (2 focused), tall at 0.6; workspace 3: window 4, full; the
  /// third workspace is current.
  private func arrangement() -> WorkspaceStack {
    var stack = WorkspaceStack(count: 4)
    var first = Workspace(layout: .tall, parameters: LayoutParameters(mainRatio: 0.6))
    for raw in [1, 2, 3] as [UInt32] { first.insert(WindowID(raw)) }
    first.setFocus(WindowID(2))
    stack[0] = first
    var third = Workspace(layout: .full)
    third.insert(WindowID(4))
    stack[2] = third
    stack.select(2)
    return stack
  }

  private func saved(_ stack: WorkspaceStack) -> SavedState {
    SavedState(
      stack: stack, floated: [WindowID(9)], tilingEnabled: true,
      originalFrames: [WindowID(1): CGRect(x: 10, y: 20, width: 300, height: 200)])
  }

  @Test func aStackComesBackAsItWas() {
    let stack = arrangement()
    #expect(saved(stack).stack(count: 4) { _ in true } == stack)
  }

  @Test func windowsThatClosedAreDroppedAndFocusMovesOn() {
    let restored = saved(arrangement()).stack(count: 4) { $0 != WindowID(2) }
    #expect(restored[0].windows == [WindowID(1), WindowID(3)])
    #expect(restored[0].focused == nil, "the focused window closed")
    #expect(restored[2].windows == [WindowID(4)])
  }

  @Test func fewerWorkspacesDropTheRestAndFallBackToTheFirst() {
    let restored = saved(arrangement()).stack(count: 2) { _ in true }
    #expect(restored.count == 2)
    #expect(restored.currentIndex == 0)
    #expect(restored[0].windows == [WindowID(1), WindowID(2), WindowID(3)])
  }

  @Test func theFileRoundTrips() throws {
    let path = NSTemporaryDirectory() + "tyler-state-\(UUID().uuidString)/tyler.state.json"
    defer { try? FileManager.default.removeItem(atPath: path) }
    let state = saved(arrangement())
    try state.write(to: path)
    #expect(try SavedState.read(from: path) == state)
  }

  @Test func noFileIsNoState() throws {
    #expect(try SavedState.read(from: "/tmp/tyler-no-such-state.json") == nil)
  }

  @Test func anotherVersionIsRefused() throws {
    let path = NSTemporaryDirectory() + "tyler-state-\(UUID().uuidString).json"
    defer { try? FileManager.default.removeItem(atPath: path) }
    var state = saved(arrangement())
    state.version = SavedState.currentVersion + 1
    try state.write(to: path)
    #expect(throws: SavedStateError.unknownVersion(path: path, version: state.version)) {
      try SavedState.read(from: path)
    }
  }

  @Test func aBrokenFileIsAnError() throws {
    let path = NSTemporaryDirectory() + "tyler-state-\(UUID().uuidString).json"
    defer { try? FileManager.default.removeItem(atPath: path) }
    try Data("{".utf8).write(to: URL(fileURLWithPath: path))
    #expect(throws: SavedStateError.self) { try SavedState.read(from: path) }
  }
}
