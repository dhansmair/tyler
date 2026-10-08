import MWMCore

/// The server's picture of which windows exist. Applying events is idempotent, because the
/// Accessibility API can report a window's first move before (or twice after) its creation.
struct WindowRegistry: Sendable {
  private var storage: [WindowID: WindowInfo] = [:]
  private var order: [WindowID] = []
  private(set) var focusedID: WindowID?

  /// Windows in the order they were first seen, with `isFocused` derived from `focusedID`.
  var windows: [WindowInfo] {
    order.compactMap { windowID in
      storage[windowID].map { window in
        var copy = window
        copy.isFocused = windowID == focusedID
        return copy
      }
    }
  }

  var count: Int { order.count }

  /// One window as last reported. `isFocused` is not derived here; use `windows` for that.
  func window(withID windowID: WindowID) -> WindowInfo? {
    storage[windowID]
  }

  /// Replaces everything with `snapshot`. Focus follows the window flagged `isFocused`.
  mutating func replaceAll(_ snapshot: [WindowInfo]) {
    storage = [:]
    order = []
    focusedID = nil
    for window in snapshot {
      upsert(window)
      if window.isFocused { focusedID = window.id }
    }
  }

  mutating func apply(_ event: WindowEvent) {
    switch event {
    case .created(let window), .updated(let window):
      upsert(window)
    case .destroyed(let windowID):
      storage[windowID] = nil
      order.removeAll { $0 == windowID }
      if focusedID == windowID { focusedID = nil }
    case .focused(let windowID):
      // Stored even if the window isn't known yet: its `created` event may still be on the way.
      focusedID = windowID
    }
  }

  private mutating func upsert(_ window: WindowInfo) {
    if storage.updateValue(window, forKey: window.id) == nil {
      order.append(window.id)
    }
  }
}
