import CoreGraphics
import Foundation

/// A snapshot of one window. Frames are in Accessibility coordinates: the origin is the top-left
/// corner of the primary display and y grows downwards.
package struct WindowInfo: Codable, Equatable, Sendable, Identifiable {
  package var id: WindowID
  package var processID: Int32
  package var appName: String
  package var bundleID: String?
  package var title: String
  package var frame: CGRect
  package var kind: WindowKind
  package var isMinimized: Bool
  package var isFullscreen: Bool
  package var isFocused: Bool
  /// Filled in by the server when answering a request; `nil` when no display is known.
  package var displayID: UInt32?
  /// The number tyler gives that display (1 is the primary); set only for `list`.
  package var displayNumber: Int?
  /// Also server-filled: the 1-based position in the tiling list (1 is the master), or `nil` if
  /// the window isn't tiled.
  package var slot: Int?
  /// Also server-filled: the number of the workspace the window is tiled on, or `nil`.
  package var workspace: Int?
  /// Also server-filled: the user floated this window, so tiling leaves it alone.
  package var isFloated: Bool

  package init(
    id: WindowID,
    processID: Int32,
    appName: String,
    bundleID: String? = nil,
    title: String = "",
    frame: CGRect,
    kind: WindowKind = .standard,
    isMinimized: Bool = false,
    isFullscreen: Bool = false,
    isFocused: Bool = false,
    displayID: UInt32? = nil,
    slot: Int? = nil,
    workspace: Int? = nil,
    isFloated: Bool = false
  ) {
    self.id = id
    self.processID = processID
    self.appName = appName
    self.bundleID = bundleID
    self.title = title
    self.frame = frame
    self.kind = kind
    self.isMinimized = isMinimized
    self.isFullscreen = isFullscreen
    self.isFocused = isFocused
    self.displayID = displayID
    self.slot = slot
    self.workspace = workspace
    self.isFloated = isFloated
  }

  /// Whether a layout may later place this window: a normal window that is on screen.
  package var isTileable: Bool {
    kind == .standard && !isMinimized && !isFullscreen
  }
}

extension WindowInfo {
  /// How the log names a window: `#7349 (Firefox)`, by its app and never its title, which may
  /// hold a page or a document the user wouldn't want in a log file; just `#7349` when nothing is
  /// known about it.
  package static func logName(_ windowID: WindowID, _ info: WindowInfo?) -> String {
    guard let info else { return "#\(windowID.rawValue)" }
    return "#\(windowID.rawValue) (\(info.appName))"
  }
}
