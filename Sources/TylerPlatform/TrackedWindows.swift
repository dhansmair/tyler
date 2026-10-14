import ApplicationServices
import TylerCore

/// The windows `AXBackend` tracks: each one's element, its app, and how it was last read, so a
/// move or resize can be reported after reading less of it.
struct TrackedWindows {
  private struct Entry {
    let element: AXUIElement
    let processID: pid_t
    var lastRead: WindowInfo?
  }

  private var entries: [WindowID: Entry] = [:]

  var ids: [WindowID] { entries.keys.sorted() }

  func contains(_ windowID: WindowID) -> Bool { entries[windowID] != nil }
  func element(of windowID: WindowID) -> AXUIElement? { entries[windowID]?.element }
  func processID(of windowID: WindowID) -> pid_t? { entries[windowID]?.processID }
  func lastRead(of windowID: WindowID) -> WindowInfo? { entries[windowID]?.lastRead }

  func ids(ownedBy processID: pid_t) -> [WindowID] {
    entries.filter { $0.value.processID == processID }.map(\.key)
  }

  /// The window `element` stands for, found by identity: for an element that can't be asked for
  /// its id any more (destroyed).
  func identify(_ element: AXUIElement) -> WindowID? {
    entries.first { CFEqual($0.value.element, element) }?.key
  }

  mutating func track(_ element: AXUIElement, as windowID: WindowID, ownedBy processID: pid_t) {
    entries[windowID] = Entry(element: element, processID: processID)
  }

  /// Whether the window was tracked.
  mutating func forget(_ windowID: WindowID) -> Bool {
    entries.removeValue(forKey: windowID) != nil
  }

  mutating func forgetAll() {
    entries = [:]
  }

  /// Reads the window in full, keeping the result as its last read.
  mutating func read(_ windowID: WindowID, isFocused: Bool) -> WindowInfo? {
    guard let entry = entries[windowID],
      let info = WindowInfo.read(
        entry.element, id: windowID, processID: entry.processID, known: entry.lastRead,
        isFocused: isFocused)
    else { return nil }
    entries[windowID]?.lastRead = info
    return info
  }

  /// The last read with a new frame (and full screen state), kept as the last read.
  mutating func note(
    _ frame: CGRect, isFullscreen: Bool? = nil, of windowID: WindowID, isFocused: Bool
  ) -> WindowInfo? {
    guard var info = entries[windowID]?.lastRead else { return nil }
    info.frame = frame
    if let isFullscreen { info.isFullscreen = isFullscreen }
    info.isFocused = isFocused
    entries[windowID]?.lastRead = info
    return info
  }
}
