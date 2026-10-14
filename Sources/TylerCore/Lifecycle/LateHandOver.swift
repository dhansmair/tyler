import CoreGraphics

/// The part of a hand-over whose windows weren't there when the next tylerd took it over: their
/// app answered late, or the screen was locked (macOS then shows no windows at all). Each window
/// gets its place back when it appears. Nothing expires: the state file is refused when older
/// than `SavedState.maximumAge`, and a window that turns up with a handed-over ID but another
/// app's process ID is a new window, which the state no longer waits for.
package struct LateHandOver: Equatable, Sendable {
  /// What it did with the windows given to `restore`.
  package struct Outcome: Equatable, Sendable {
    /// The windows put back.
    package var restored: [WindowID] = []
    /// Where the windows put back were before tylerd first moved them.
    package var originalFrames: [WindowID: CGRect] = [:]
  }

  private struct Expected: Equatable, Sendable {
    /// `nil` in files from before the state named each window's app.
    let processID: Int32?
    /// Where it was tiled; `nil` for a floated window.
    let place: Place?
    let originalFrame: CGRect?
  }

  private struct Place: Equatable, Sendable {
    let number: Int
    /// The windows after it on its workspace, in order: it goes back before the first of them
    /// that is there, so a workspace that comes back one window at a time keeps its order.
    let followers: [WindowID]
    let wasFocused: Bool
  }

  private var expected: [WindowID: Expected] = [:]

  package init() {}

  /// What `saved` names beyond the windows in `taken`.
  package init(_ saved: SavedState, taken: Set<WindowID>) {
    let frames = Dictionary(
      saved.originalFrames.map { ($0.id, $0.frame) }, uniquingKeysWith: { first, _ in first })
    let processIDs = Dictionary(
      (saved.apps ?? []).map { ($0.id, $0.processID) }, uniquingKeysWith: { first, _ in first })
    for (number, workspace) in saved.numberedWorkspaces {
      for (index, windowID) in workspace.windows.enumerated() where !taken.contains(windowID) {
        let place = Place(
          number: number, followers: Array(workspace.windows[(index + 1)...]),
          wasFocused: workspace.focused == windowID)
        expected[windowID] = Expected(
          processID: processIDs[windowID], place: place, originalFrame: frames[windowID])
      }
    }
    for windowID in saved.floated where !taken.contains(windowID) {
      expected[windowID] = Expected(
        processID: processIDs[windowID], place: nil, originalFrame: frames[windowID])
    }
  }

  package var isEmpty: Bool { expected.isEmpty }

  /// Puts the windows of `windows` that it waits for back: a floated one into `floatedWindows`,
  /// a tiled one onto its workspace in `rows`. A tiled one that can't be tiled yet (it appears
  /// before it can) waits.
  @discardableResult
  package mutating func restore(
    _ windows: [WindowInfo], into rows: inout DisplayRows,
    floated floatedWindows: inout Set<WindowID>
  ) -> Outcome {
    var outcome = Outcome()
    for window in windows {
      guard let expected = expected[window.id] else { continue }
      if let processID = expected.processID, processID != window.processID {
        self.expected[window.id] = nil
        continue
      }
      guard let place = expected.place else {
        self.expected[window.id] = nil
        floatedWindows.insert(window.id)
        outcome.note(window.id, originalFrame: expected.originalFrame)
        continue
      }
      guard window.isTileable else { continue }
      self.expected[window.id] = nil
      if Self.put(window.id, back: place, into: &rows) {
        outcome.note(window.id, originalFrame: expected.originalFrame)
      }
    }
    return outcome
  }

  private static func put(
    _ windowID: WindowID, back place: Place, into rows: inout DisplayRows
  ) -> Bool {
    guard rows.location(of: windowID) == nil,
      let location = rows.location(ofNumber: place.number)
    else { return false }
    var workspace = rows[location.position][location.index]
    workspace.insert(windowID, before: place.followers.first(where: workspace.contains))
    if place.wasFocused { workspace.setFocus(windowID) }
    rows[location.position][location.index] = workspace
    return true
  }
}

extension LateHandOver.Outcome {
  fileprivate mutating func note(_ windowID: WindowID, originalFrame: CGRect?) {
    restored.append(windowID)
    originalFrames[windowID] = originalFrame
  }
}
