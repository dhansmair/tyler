import ApplicationServices
import CoreGraphics
import TylerCore

/// The typed Accessibility vocabulary tylerd speaks, over an `AXClient`. Reads return `nil`
/// instead of throwing: an app that is busy, quitting or hostile to Accessibility is routine, not
/// exceptional.
struct AXBridge: Sendable {
  /// How long a single AX call may block on an unresponsive app before failing.
  static let messagingTimeout: Float = 1.0

  let client: any AXClient

  /// Applies `messagingTimeout` to every element, window elements included: a timeout set on one
  /// element doesn't carry over to the elements read from it, which would otherwise wait the
  /// system default (about 6 s) on a hung app.
  func limitMessagingTimeout() {
    _ = client.setMessagingTimeout(Self.messagingTimeout, of: client.createSystemWide())
  }

  func applicationElement(processID: pid_t) -> AXUIElement {
    let element = client.createApplication(processID)
    _ = client.setMessagingTimeout(Self.messagingTimeout, of: element)
    return element
  }

  func windowID(of element: AXUIElement) -> WindowID? {
    guard let raw = client.windowNumber(of: element), raw != 0 else { return nil }
    return WindowID(raw)
  }

  func windows(of application: AXUIElement) -> [AXUIElement] {
    value(kAXWindowsAttribute, of: application) as? [AXUIElement] ?? []
  }

  func focusedWindow(of application: AXUIElement) -> AXUIElement? {
    element(kAXFocusedWindowAttribute, of: application)
  }

  func element(_ attribute: String, of element: AXUIElement) -> AXUIElement? {
    guard let raw = value(attribute, of: element),
      CFGetTypeID(raw) == AXUIElementGetTypeID()
    else { return nil }
    return unsafeDowncast(raw, to: AXUIElement.self)
  }

  /// The window's frame in Accessibility coordinates, or `nil` if either part can't be read.
  /// One round trip to the app.
  func frame(of element: AXUIElement) -> CGRect? {
    let values = values([kAXPositionAttribute, kAXSizeAttribute], of: element)
    return frame(position: values[0], size: values[1])
  }

  /// The frame and whether the window is in native full screen, in one round trip.
  func frameAndFullscreen(of element: AXUIElement) -> (CGRect, Bool?)? {
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
    var buttons: WindowButtons
    /// Read only when `WindowKind.classify` depends on it.
    var isResizable: Bool?
  }

  func windowAttributes(of element: AXUIElement) -> WindowAttributes? {
    let values = values(
      [
        kAXPositionAttribute, kAXSizeAttribute, kAXTitleAttribute, kAXRoleAttribute,
        kAXSubroleAttribute, kAXMinimizedAttribute, "AXFullScreen",
        kAXCloseButtonAttribute, kAXMinimizeButtonAttribute, kAXFullScreenButtonAttribute,
      ], of: element)
    guard let frame = frame(position: values[0], size: values[1]) else { return nil }
    var buttons: WindowButtons = []
    for (button, value) in zip([WindowButtons.close, .minimize, .fullScreen], values[7...])
    where value != nil {
      buttons.insert(button)
    }
    let role = values[3] as? String
    let subrole = values[4] as? String
    let isResizable =
      WindowKind.dependsOnResizability(role: role, subrole: subrole, buttons: buttons)
      ? client.isAttributeSettable(kAXSizeAttribute, of: element) : nil
    return WindowAttributes(
      frame: frame, title: values[2] as? String, role: role, subrole: subrole,
      isMinimized: values[5] as? Bool, isFullscreen: values[6] as? Bool, buttons: buttons,
      isResizable: isResizable)
  }

  // MARK: - Writing

  /// Moves and resizes a window. Size is set, then position, then size again: a window moved to
  /// a screen edge can be clamped, which changes the size the first call was made for. Returns
  /// the first error, or `.success`.
  func setFrame(_ frame: CGRect, of element: AXUIElement) -> AXError {
    var origin = frame.origin
    var size = frame.size
    guard let axPosition = AXValueCreate(.cgPoint, &origin),
      let axSize = AXValueCreate(.cgSize, &size)
    else { return .failure }

    for (attribute, value) in [
      (kAXSizeAttribute, axSize), (kAXPositionAttribute, axPosition), (kAXSizeAttribute, axSize),
    ] {
      let status = client.setAttributeValue(attribute, value, of: element)
      if status != .success { return status }
    }
    return .success
  }

  /// Moves a window without resizing it: one position write, cheap enough for animation steps.
  func write(_ write: FrameWrite, to element: AXUIElement) -> AXError {
    switch write {
    case .position(let origin): return setPosition(origin, of: element)
    case .size(var size):
      guard let value = AXValueCreate(.cgSize, &size) else { return .failure }
      return client.setAttributeValue(kAXSizeAttribute, value, of: element)
    }
  }

  func setPosition(_ origin: CGPoint, of element: AXUIElement) -> AXError {
    var point = origin
    guard let axPosition = AXValueCreate(.cgPoint, &point) else { return .failure }
    return client.setAttributeValue(kAXPositionAttribute, axPosition, of: element)
  }

  /// Brings a window to the front and gives it keyboard focus: the owning app is made frontmost
  /// (an accessory app like tylerd can't rely on `NSRunningApplication.activate`, which the SDK
  /// documents as cooperative and not guaranteed), then the window is raised and marked main.
  func raise(window: AXUIElement, in processID: pid_t) -> AXError {
    var status = makeFrontmost(processID: processID)
    if status != .success { return status }
    status = client.performAction(kAXRaiseAction, on: window)
    if status != .success { return status }
    // Best effort: some windows refuse these, but the raise above already did the visible part.
    _ = client.setAttributeValue(kAXMainAttribute, kCFBooleanTrue, of: window)
    _ = client.setAttributeValue(kAXFocusedAttribute, kCFBooleanTrue, of: window)
    return .success
  }

  /// Presses the window's close button. A window without one (some panels) can't be closed.
  func close(window: AXUIElement) -> AXError {
    guard let button = element(kAXCloseButtonAttribute, of: window) else {
      return .actionUnsupported
    }
    return client.performAction(kAXPressAction, on: button)
  }

  /// Makes an app frontmost, the same way for tylerd itself as for any other app.
  func makeFrontmost(processID: pid_t) -> AXError {
    client.setAttributeValue(
      kAXFrontmostAttribute, kCFBooleanTrue, of: applicationElement(processID: processID))
  }

  // MARK: - Notifications

  enum ObservingFailure: Error {
    case create(AXError)
    case register(String, AXError)
  }

  /// Notifications registered on the app element itself.
  static let appNotifications = [
    kAXWindowCreatedNotification,
    kAXFocusedWindowChangedNotification,
  ]

  /// Notifications registered on every window element.
  static let windowNotifications = [
    kAXUIElementDestroyedNotification,
    kAXMovedNotification,
    kAXResizedNotification,
    kAXWindowMiniaturizedNotification,
    kAXWindowDeminiaturizedNotification,
    kAXTitleChangedNotification,
  ]

  /// Delivers the app's notifications to `handler` on the main thread, starting with the
  /// app-level ones. Throws if the app refuses, which is common for an app that has only just
  /// launched; callers retry.
  @MainActor
  func observe(
    _ application: AXUIElement, processID: pid_t,
    handler: @escaping @MainActor (String, AXUIElement) -> Void
  ) throws(ObservingFailure) {
    let status = client.createObserver(processID: processID, handler: handler)
    guard status == .success else { throw .create(status) }
    for name in Self.appNotifications {
      let status = add(name, to: application, of: processID)
      guard status == .success else {
        stopObserving(processID: processID)
        throw .register(name, status)
      }
    }
  }

  /// Subscribes to the per-window notifications. Failures are reported but not fatal: a window
  /// that can't be observed is still listed, it just won't update live.
  @MainActor
  func observe(window: AXUIElement, processID: pid_t) -> [ObservingFailure] {
    Self.windowNotifications.compactMap { name in
      let status = add(name, to: window, of: processID)
      return status == .success ? nil : .register(name, status)
    }
  }

  /// Stops the app's notifications; none is delivered after this.
  @MainActor func stopObserving(processID: pid_t) { client.removeObserver(processID: processID) }

  /// `notificationAlreadyRegistered` happens when a window is observed twice; harmless.
  @MainActor
  private func add(_ name: String, to element: AXUIElement, of processID: pid_t) -> AXError {
    let status = client.addNotification(name, to: element, of: processID)
    return status == .notificationAlreadyRegistered ? .success : status
  }

  // MARK: - Private

  private func value(_ attribute: String, of element: AXUIElement) -> CFTypeRef? {
    client.copyAttributeValue(attribute, of: element)
  }

  /// Reads several attributes in one call. Each entry is `nil` where that attribute couldn't be
  /// read; every entry is `nil` if the call itself failed.
  private func values(_ attributes: [String], of element: AXUIElement) -> [CFTypeRef?] {
    guard let array = client.copyAttributeValues(attributes, of: element),
      array.count == attributes.count
    else { return Array(repeating: nil, count: attributes.count) }
    // An attribute that couldn't be read comes back as an AXValue holding its error.
    return array.map { value in isError(value) ? nil : value }
  }

  private func isError(_ value: CFTypeRef) -> Bool {
    CFGetTypeID(value) == AXValueGetTypeID()
      && AXValueGetType(unsafeDowncast(value, to: AXValue.self)) == .axError
  }

  private func frame(position: CFTypeRef?, size: CFTypeRef?) -> CGRect? {
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

extension AXBridge.ObservingFailure: CustomStringConvertible {
  var description: String {
    switch self {
    case .create(let status): "observer: AX error \(status.rawValue)"
    case .register(let name, let status): "\(name): AX error \(status.rawValue)"
    }
  }
}
