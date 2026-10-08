import ApplicationServices
import CoreGraphics
import MWMCore

// Private but long-standing API (used by every macOS window manager) that maps an Accessibility
// element to its `CGWindowID`. It needs no special permission.
@_silgen_name("_AXUIElementGetWindow")
private func axGetWindow(
  _ element: AXUIElement,
  _ windowID: UnsafeMutablePointer<CGWindowID>
) -> AXError

/// Thin, stateless wrappers over the C Accessibility API. Reads return `nil` instead of throwing:
/// an app that is busy, quitting or hostile to Accessibility is routine, not exceptional.
enum AXBridge {
  /// How long a single AX call may block on an unresponsive app before failing.
  static let messagingTimeout: Float = 1.0

  static func applicationElement(processID: pid_t) -> AXUIElement {
    let element = AXUIElementCreateApplication(processID)
    AXUIElementSetMessagingTimeout(element, messagingTimeout)
    return element
  }

  static func windowID(of element: AXUIElement) -> WindowID? {
    var raw = CGWindowID(0)
    guard axGetWindow(element, &raw) == .success, raw != 0 else { return nil }
    return WindowID(raw)
  }

  static func windows(of application: AXUIElement) -> [AXUIElement] {
    value(kAXWindowsAttribute, of: application) as? [AXUIElement] ?? []
  }

  static func focusedWindow(of application: AXUIElement) -> AXUIElement? {
    element(kAXFocusedWindowAttribute, of: application)
  }

  static func string(_ attribute: String, of element: AXUIElement) -> String? {
    value(attribute, of: element) as? String
  }

  static func bool(_ attribute: String, of element: AXUIElement) -> Bool? {
    value(attribute, of: element) as? Bool
  }

  static func element(_ attribute: String, of element: AXUIElement) -> AXUIElement? {
    guard let raw = value(attribute, of: element),
      CFGetTypeID(raw) == AXUIElementGetTypeID()
    else { return nil }
    return unsafeDowncast(raw, to: AXUIElement.self)
  }

  /// The window's frame in Accessibility coordinates, or `nil` if either part can't be read.
  static func frame(of element: AXUIElement) -> CGRect? {
    guard let axPosition = axValue(kAXPositionAttribute, of: element),
      let axSize = axValue(kAXSizeAttribute, of: element)
    else { return nil }
    var origin = CGPoint.zero
    var size = CGSize.zero
    guard AXValueGetValue(axPosition, .cgPoint, &origin),
      AXValueGetValue(axSize, .cgSize, &size)
    else { return nil }
    return CGRect(origin: origin, size: size)
  }

  // MARK: - Private

  private static func value(_ attribute: String, of element: AXUIElement) -> CFTypeRef? {
    var result: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success
    else { return nil }
    return result
  }

  private static func axValue(_ attribute: String, of element: AXUIElement) -> AXValue? {
    guard let raw = value(attribute, of: element), CFGetTypeID(raw) == AXValueGetTypeID()
    else { return nil }
    return unsafeDowncast(raw, to: AXValue.self)
  }
}
