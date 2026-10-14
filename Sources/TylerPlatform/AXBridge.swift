import ApplicationServices
import CoreGraphics
import TylerCore

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

  /// Applies `messagingTimeout` to every element, window elements included: a timeout set on one
  /// element doesn't carry over to the elements read from it, which would otherwise wait the
  /// system default (about 6 s) on a hung app.
  static func limitMessagingTimeout() {
    AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), messagingTimeout)
  }

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

  static func element(_ attribute: String, of element: AXUIElement) -> AXUIElement? {
    guard let raw = value(attribute, of: element),
      CFGetTypeID(raw) == AXUIElementGetTypeID()
    else { return nil }
    return unsafeDowncast(raw, to: AXUIElement.self)
  }

  /// The window's frame in Accessibility coordinates, or `nil` if either part can't be read.
  /// One round trip to the app.
  static func frame(of element: AXUIElement) -> CGRect? {
    let values = values([kAXPositionAttribute, kAXSizeAttribute], of: element)
    return frame(position: values[0], size: values[1])
  }

  /// The frame and whether the window is in native full screen, in one round trip.
  static func frameAndFullscreen(of element: AXUIElement) -> (CGRect, Bool?)? {
    let values = values([kAXPositionAttribute, kAXSizeAttribute, "AXFullScreen"], of: element)
    return frame(position: values[0], size: values[1]).map { ($0, values[2] as? Bool) }
  }

  /// What tylerd needs to know about a window, read in one round trip to the app: each
  /// attribute read on its own would wait for the app again (up to `messagingTimeout` each when
  /// it hangs). `nil` if the frame can't be read.
  struct WindowAttributes {
    var frame: CGRect
    var title: String?
    var role: String?
    var subrole: String?
    var isMinimized: Bool?
    var isFullscreen: Bool?
  }

  static func windowAttributes(of element: AXUIElement) -> WindowAttributes? {
    let values = values(
      [
        kAXPositionAttribute, kAXSizeAttribute, kAXTitleAttribute, kAXRoleAttribute,
        kAXSubroleAttribute, kAXMinimizedAttribute, "AXFullScreen",
      ], of: element)
    guard let frame = frame(position: values[0], size: values[1]) else { return nil }
    return WindowAttributes(
      frame: frame, title: values[2] as? String, role: values[3] as? String,
      subrole: values[4] as? String, isMinimized: values[5] as? Bool,
      isFullscreen: values[6] as? Bool)
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
  static func write(_ write: FrameWrite, to element: AXUIElement) -> AXError {
    switch write {
    case .position(let origin): return setPosition(origin, of: element)
    case .size(var size):
      guard let value = AXValueCreate(.cgSize, &size) else { return .failure }
      return AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value)
    }
  }

  static func setPosition(_ origin: CGPoint, of element: AXUIElement) -> AXError {
    var point = origin
    guard let axPosition = AXValueCreate(.cgPoint, &point) else { return .failure }
    return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, axPosition)
  }

  /// Brings a window to the front and gives it keyboard focus: the owning app is made frontmost
  /// (an accessory app like tylerd can't rely on `NSRunningApplication.activate`, which the SDK
  /// documents as cooperative and not guaranteed), then the window is raised and marked main.
  static func raise(window: AXUIElement, in processID: pid_t) -> AXError {
    var status = makeFrontmost(processID: processID)
    if status != .success { return status }
    status = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    if status != .success { return status }
    // Best effort: some windows refuse these, but the raise above already did the visible part.
    _ = AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
    _ = AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    return .success
  }

  /// Presses the window's close button. A window without one (some panels) can't be closed.
  static func close(window: AXUIElement) -> AXError {
    guard let button = element(kAXCloseButtonAttribute, of: window) else {
      return .actionUnsupported
    }
    return AXUIElementPerformAction(button, kAXPressAction as CFString)
  }

  /// Makes an app frontmost, the same way for tylerd itself as for any other app.
  static func makeFrontmost(processID: pid_t) -> AXError {
    AXUIElementSetAttributeValue(
      applicationElement(processID: processID), kAXFrontmostAttribute as CFString, kCFBooleanTrue)
  }

  // MARK: - Private

  private static func value(_ attribute: String, of element: AXUIElement) -> CFTypeRef? {
    var result: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success
    else { return nil }
    return result
  }

  /// Reads several attributes in one call. Each entry is `nil` where that attribute couldn't be
  /// read; every entry is `nil` if the call itself failed.
  private static func values(_ attributes: [String], of element: AXUIElement) -> [CFTypeRef?] {
    var result: CFArray?
    let status = AXUIElementCopyMultipleAttributeValues(
      element, attributes as CFArray, AXCopyMultipleAttributeOptions(rawValue: 0), &result)
    guard status == .success, let array = result as [AnyObject]?, array.count == attributes.count
    else { return Array(repeating: nil, count: attributes.count) }
    // An attribute that couldn't be read comes back as an AXValue holding its error.
    return array.map { value in isError(value) ? nil : value }
  }

  private static func isError(_ value: CFTypeRef) -> Bool {
    CFGetTypeID(value) == AXValueGetTypeID()
      && AXValueGetType(unsafeDowncast(value, to: AXValue.self)) == .axError
  }

  private static func frame(position: CFTypeRef?, size: CFTypeRef?) -> CGRect? {
    guard let position, let size, CFGetTypeID(position) == AXValueGetTypeID(),
      CFGetTypeID(size) == AXValueGetTypeID()
    else { return nil }
    var origin = CGPoint.zero
    var extent = CGSize.zero
    guard AXValueGetValue(unsafeDowncast(position, to: AXValue.self), .cgPoint, &origin),
      AXValueGetValue(unsafeDowncast(size, to: AXValue.self), .cgSize, &extent)
    else { return nil }
    return CGRect(origin: origin, size: extent)
  }
}
