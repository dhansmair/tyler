import ApplicationServices
import TylerCore

/// The windows whose notifications came in a burst, each to be read once, as deeply as the
/// deepest of them needs. Every step of a slide or resize echoes back as several notifications
/// per window, and each read is a round trip to an app that may be busy redrawing.
struct PendingReads {
  enum Depth: Comparable {
    /// A move changes nothing but the frame.
    case frame
    /// A resize may also be the window going full screen.
    case frameAndFullscreen
    case full
  }

  private var depths: [WindowID: Depth] = [:]

  var isEmpty: Bool { depths.isEmpty }

  /// Notes that `windowID` must be read again for `notification`; `false` for a notification
  /// that isn't put off.
  mutating func note(_ notification: String, for windowID: WindowID) -> Bool {
    let depth: Depth
    switch notification {
    case kAXMovedNotification: depth = .frame
    case kAXResizedNotification: depth = .frameAndFullscreen
    case kAXTitleChangedNotification: depth = .full
    default: return false
    }
    depths[windowID] = max(depths[windowID] ?? depth, depth)
    return true
  }

  mutating func forget(_ windowID: WindowID) {
    depths[windowID] = nil
  }

  mutating func takeAll() -> [(windowID: WindowID, depth: Depth)] {
    defer { depths = [:] }
    return depths.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
  }
}
