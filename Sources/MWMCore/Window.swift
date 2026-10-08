import CoreGraphics
import Foundation

/// The system-wide window number (`CGWindowID`), stable for the lifetime of a window.
public struct WindowID: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
  public let rawValue: UInt32

  public init(_ rawValue: UInt32) {
    self.rawValue = rawValue
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    rawValue = try container.decode(UInt32.self)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  public static func < (lhs: WindowID, rhs: WindowID) -> Bool {
    lhs.rawValue < rhs.rawValue
  }

  public var description: String { String(rawValue) }
}

/// What sort of window this is, derived from its Accessibility role and subrole.
public enum WindowKind: String, Codable, Sendable {
  case standard
  case dialog
  case floating
  case other

  /// Maps raw Accessibility strings to a kind. Unknown or missing values are `.other`.
  public static func classify(role: String?, subrole: String?) -> WindowKind {
    switch (role, subrole) {
    case ("AXSheet", _), (_, "AXDialog"), (_, "AXSystemDialog"):
      return .dialog
    case (_, "AXFloatingWindow"), (_, "AXSystemFloatingWindow"):
      return .floating
    case ("AXWindow", "AXStandardWindow"):
      return .standard
    default:
      return .other
    }
  }
}

/// A snapshot of one window. Frames are in Accessibility coordinates: the origin is the top-left
/// corner of the primary display and y grows downwards.
public struct WindowInfo: Codable, Equatable, Sendable, Identifiable {
  public var id: WindowID
  public var processID: Int32
  public var appName: String
  public var bundleID: String?
  public var title: String
  public var frame: CGRect
  public var kind: WindowKind
  public var isMinimized: Bool
  public var isFullscreen: Bool
  public var isFocused: Bool
  /// Filled in by the server when answering a request; `nil` when no display is known.
  public var displayID: UInt32?

  public init(
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
    displayID: UInt32? = nil
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
  }

  /// Whether a layout may later place this window: a normal window that is on screen.
  public var isTileable: Bool {
    kind == .standard && !isMinimized && !isFullscreen
  }
}
