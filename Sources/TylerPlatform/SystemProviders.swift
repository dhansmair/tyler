import AppKit
import ApplicationServices
import TylerCore
import TylerServer

/// Asks macOS whether this process (or the terminal app hosting it) may use Accessibility.
@MainActor
public final class SystemAccessibilityGate: AccessibilityGate {
  public init() {}

  public var isTrusted: Bool { AXIsProcessTrusted() }

  public func prompt() {
    // The literal is the value of `kAXTrustedCheckOptionPrompt`; the constant itself is a
    // mutable global, which Swift 6 strict concurrency rejects.
    let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
  }
}

/// Reads the connected displays from AppKit and converts them to Accessibility coordinates.
@MainActor
public final class ScreenDisplayProvider: DisplayProvider {
  public init() {}

  public var displays: [DisplayInfo] {
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
        frame: DisplayGeometry.axRect(fromAppKit: screen.frame, primaryScreenHeight: primaryHeight),
        visibleFrame: DisplayGeometry.axRect(
          fromAppKit: screen.visibleFrame,
          primaryScreenHeight: primaryHeight
        )
      )
    }
  }
}
