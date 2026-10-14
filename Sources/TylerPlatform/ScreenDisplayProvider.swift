import AppKit
import ApplicationServices
import TylerCore
import TylerServer

/// Reads the connected displays from AppKit and converts them to Accessibility coordinates.
@MainActor
package final class ScreenDisplayProvider: DisplayProvider {
  package let changes: AsyncStream<Void>
  private let continuation: AsyncStream<Void>.Continuation
  /// The observer of screen changes; it lives as long as the provider, which is tylerd's.
  private var token: NSObjectProtocol?

  package init() {
    (changes, continuation) = AsyncStream.makeStream(of: Void.self)
    let continuation = continuation
    token = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
    ) { _ in
      continuation.yield()
    }
  }

  package var displays: [DisplayInfo] {
    let screens = NSScreen.screens
    // AppKit lists the primary display (the one with the menu bar) first. Its height is the
    // origin for converting every display's bottom-left coordinates to top-left.
    guard let primaryHeight = screens.first?.frame.height else { return [] }
    return screens.compactMap { screen in
      guard
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
          as? NSNumber
      else { return nil }
      return DisplayInfo(
        id: number.uint32Value,
        key: Self.key(of: number.uint32Value),
        frame: DisplayGeometry.axRect(fromAppKit: screen.frame, primaryScreenHeight: primaryHeight),
        visibleFrame: DisplayGeometry.axRect(
          fromAppKit: screen.visibleFrame,
          primaryScreenHeight: primaryHeight
        )
      )
    }
  }

  /// The display's UUID, which stays the same when it is unplugged, sleeps or the Mac restarts
  /// (measured; see `devdocs/macos-behaviour.md`); its id if macOS has no UUID for it.
  private static func key(of displayID: CGDirectDisplayID) -> DisplayKey {
    guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
      let text = CFUUIDCreateString(nil, uuid) as String?
    else { return DisplayKey("\(displayID)") }
    return DisplayKey(text)
  }
}
