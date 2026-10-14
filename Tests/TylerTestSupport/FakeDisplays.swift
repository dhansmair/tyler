import CoreGraphics
import TylerCore

@testable import TylerServer

@MainActor
package final class FakeDisplays: DisplayProvider {
  package var displays: [DisplayInfo]
  package let changes: AsyncStream<Void>
  private let continuation: AsyncStream<Void>.Continuation

  package init(displays: [DisplayInfo] = [FakeDisplays.main]) {
    self.displays = displays
    (changes, continuation) = AsyncStream.makeStream(of: Void.self)
  }

  /// Reports a change, as macOS does several times for each (see `WindowManager.displaysChanged`).
  package func sendChange() { continuation.yield() }

  package static let main = DisplayInfo(
    id: 1,
    frame: CGRect(x: 0, y: 0, width: 1800, height: 1169),
    visibleFrame: CGRect(x: 55, y: 38, width: 1745, height: 1131)
  )

  /// A second display above `main`, like an external display: it touches no edge where `main`
  /// parks windows. Display 2, with workspaces 5 to 8 by default.
  package static let secondary = DisplayInfo(
    id: 3,
    frame: CGRect(x: -397, y: -1440, width: 2560, height: 1440),
    visibleFrame: CGRect(x: -397, y: -1410, width: 2560, height: 1410)
  )

  /// A second display to the right of `main`, where `main` parks windows.
  package static let right = DisplayInfo(
    id: 2,
    frame: CGRect(x: 1800, y: 0, width: 1920, height: 1080),
    visibleFrame: CGRect(x: 1800, y: 0, width: 1920, height: 1080)
  )
}
