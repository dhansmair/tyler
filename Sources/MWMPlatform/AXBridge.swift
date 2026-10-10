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

  // MARK: - Writing

  /// Moves and resizes a window. Size is set, then position, then size again: a window moved to
  /// a screen edge can be clamped, which changes the size the first call was made for. Returns
  /// the first error, or `.success`.
  static func setFrame(_ frame: CGRect, of element: AXUIElement) -> AXError {
    var origin = frame.origin
    var size = frame.size
    guard let axPosition = AXValueCreate(.cgPoint, &origin),
      let axSize = AXValueCreate(.cgSize, &size)
    else { return .failure }

    for (attribute, value) in [
      (kAXSizeAttribute, axSize), (kAXPositionAttribute, axPosition), (kAXSizeAttribute, axSize),
    ] {
      let status = AXUIElementSetAttributeValue(element, attribute as CFString, value)
      if status != .success { return status }
    }
    return .success
  }

  /// Moves a window without resizing it: one position write, cheap enough for animation steps.
  static func setPosition(_ origin: CGPoint, of element: AXUIElement) -> AXError {
    var point = origin
    guard let axPosition = AXValueCreate(.cgPoint, &point) else { return .failure }
    return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, axPosition)
  }

  /// Brings a window to the front and gives it keyboard focus: the owning app is made frontmost
  /// (an accessory app like mwmd can't rely on `NSRunningApplication.activate`, which the SDK
  /// documents as cooperative and not guaranteed), then the window is raised and marked main.
  static func raise(window: AXUIElement, in processID: pid_t) -> AXError {
    let application = applicationElement(processID: processID)
    var status = AXUIElementSetAttributeValue(
      application, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
    if status != .success { return status }
    status = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    if status != .success { return status }
    // Best effort: some windows refuse these, but the raise above already did the visible part.
    _ = AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
    _ = AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    return .success
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
