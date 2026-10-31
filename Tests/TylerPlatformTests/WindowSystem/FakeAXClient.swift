import ApplicationServices
import Foundation
import TylerCore

@testable import TylerPlatform

/// A small Accessibility emulator: apps, their windows and the windows' attributes, with
/// application elements standing in for windows and buttons (creating one needs no permission and
/// no app; an element is told apart by the process ID it was made for). The helpers speak in
/// windows, so the tests do too. Thread safe: the step queues write from their own threads.
final class FakeAXClient: AXClient, @unchecked Sendable {
  /// What was asked of a window, in order.
  enum Call: Equatable {
    case position(CGPoint)
    case size(CGSize)
    case raise
    case main
    case focused
    case pressClose
    case isSettable(String)
  }

  private struct Window {
    let app: pid_t
    var frame: CGRect
    var role: String? = "AXWindow"
    var subrole: String?
    var buttons: WindowButtons
    var isResizable: Bool
    var isMinimized = false
    var minimumSize = CGSize.zero
  }

  private struct State {
    var appWindows: [pid_t: [WindowID]] = [:]
    var focused: [pid_t: WindowID] = [:]
    var windows: [WindowID: Window] = [:]
    var errors: [pid_t: AXError] = [:]
    var observerRefusals: [pid_t: Int] = [:]
    var handlers: [pid_t: @MainActor (String, AXUIElement) -> Void] = [:]
    var registered: Set<Registration> = []
    var calls: [WindowID: [Call]] = [:]
    var frontmostRequests: [pid_t] = []
    var gates: [WindowID: Gate] = [:]
    var isHidingWindows = false
  }

  /// A write held until the test opens it; the semaphores are safe from any thread.
  private final class Gate: Sendable {
    let entered = DispatchSemaphore(value: 0)
    let open = DispatchSemaphore(value: 0)
  }

  private struct Registration: Hashable {
    let app: pid_t
    let element: pid_t
    let notification: String
  }

  private static let windowBase: pid_t = 1_000_000
  private static let closeButtonBase: pid_t = 2_000_000

  private let lock = NSLock()
  private var state = State()

  // MARK: - Setting up

  func addWindow(
    id: UInt32, frame: CGRect, subrole: String? = "AXStandardWindow",
    buttons: WindowButtons = .all, isResizable: Bool = true, in app: pid_t
  ) {
    lock.withLock {
      state.windows[WindowID(id)] = Window(
        app: app, frame: frame, subrole: subrole, buttons: buttons, isResizable: isResizable)
      state.appWindows[app, default: []].append(WindowID(id))
    }
  }

  /// The window closes: its element is invalid from now on.
  func removeWindow(_ id: UInt32) {
    lock.withLock {
      guard let window = state.windows.removeValue(forKey: WindowID(id)) else { return }
      state.appWindows[window.app]?.removeAll { $0 == WindowID(id) }
      if state.focused[window.app] == WindowID(id) { state.focused[window.app] = nil }
    }
  }

  /// Every app lists no windows and every window's element answers as invalid, as while the screen
  /// is locked; `false` shows them again.
  func hideWindows(_ isHiding: Bool) {
    lock.withLock { state.isHidingWindows = isHiding }
  }

  /// What the user did to a window, which macOS then reports.
  func change(_ id: UInt32, frame: CGRect? = nil, isMinimized: Bool? = nil) {
    lock.withLock {
      if let frame { state.windows[WindowID(id)]?.frame = frame }
      if let isMinimized { state.windows[WindowID(id)]?.isMinimized = isMinimized }
    }
  }

  func focus(_ id: UInt32?, in app: pid_t) {
    lock.withLock { state.focused[app] = id.map { WindowID($0) } }
  }

  /// Every call to the window's element fails with `error` (`nil`: answers again).
  func answer(_ error: AXError?, from id: UInt32) {
    lock.withLock { state.errors[Self.windowBase + pid_t(id)] = error }
  }

  /// Every call to the app's elements, its windows' included, fails with `error`.
  func answer(_ error: AXError?, fromApp app: pid_t) {
    lock.withLock { state.errors[app] = error }
  }

  /// The app refuses the next `times` attempts to observe it, as a freshly launched app does.
  func refuseObserving(_ app: pid_t, times: Int) {
    lock.withLock { state.observerRefusals[app] = times }
  }

  /// The next writes to the window wait until `open(_:)`, as a busy app makes them wait.
  func hold(_ id: UInt32) {
    lock.withLock { state.gates[WindowID(id)] = Gate() }
  }

  /// Returns once a write to the held window is waiting.
  func waitUntilHeld(_ id: UInt32) {
    lock.withLock { state.gates[WindowID(id)] }?.entered.wait()
  }

  /// Lets the held writes through, after `delay` on another thread: a test that settles the
  /// window's app blocks the main thread until then.
  func open(_ id: UInt32, after delay: DispatchTimeInterval = .never) {
    guard let gate = lock.withLock({ state.gates.removeValue(forKey: WindowID(id)) }) else {
      return
    }
    if delay == .never {
      gate.open.signal()
    } else {
      DispatchQueue.global().asyncAfter(deadline: .now() + delay) { gate.open.signal() }
    }
  }

  /// The app won't make the window smaller than `size`.
  func clamp(_ id: UInt32, toAtLeast size: CGSize) {
    lock.withLock { state.windows[WindowID(id)]?.minimumSize = size }
  }

  // MARK: - AXClient

  func createApplication(_ processID: pid_t) -> AXUIElement {
    AXUIElementCreateApplication(processID)
  }

  func createSystemWide() -> AXUIElement { AXUIElementCreateSystemWide() }

  func setMessagingTimeout(_ seconds: Float, of element: AXUIElement) -> AXError { .success }

  func copyAttributeValue(_ attribute: String, of element: AXUIElement) -> CFTypeRef? {
    let key = Self.key(of: element)
    return lock.withLock { () -> CFTypeRef? in
      guard error(for: key) == nil else { return nil }
      if let windows = state.appWindows[key] {
        switch attribute {
        case kAXWindowsAttribute:
          return state.isHidingWindows ? [] as CFArray : windows.map(Self.element(of:)) as CFArray
        case kAXFocusedWindowAttribute: return state.focused[key].map(Self.element(of:))
        default: return nil
        }
      }
      guard attribute == kAXCloseButtonAttribute, let id = Self.windowID(of: key),
        state.windows[id]?.buttons.contains(.close) == true
      else { return nil }
      return AXUIElementCreateApplication(Self.closeButtonBase + pid_t(id.rawValue))
    }
  }

  func copyAttributeValues(_ attributes: [String], of element: AXUIElement) -> [AnyObject]? {
    let key = Self.key(of: element)
    return lock.withLock { () -> [AnyObject]? in
      guard error(for: key) == nil, let id = Self.windowID(of: key),
        let window = state.windows[id]
      else { return nil }
      return attributes.map { Self.value(attribute: $0, of: window) ?? Self.missing }
    }
  }

  func isAttributeSettable(_ attribute: String, of element: AXUIElement) -> Bool? {
    let key = Self.key(of: element)
    return lock.withLock {
      guard error(for: key) == nil, let id = Self.windowID(of: key),
        let window = state.windows[id]
      else { return nil }
      state.calls[id, default: []].append(.isSettable(attribute))
      return attribute == kAXSizeAttribute ? window.isResizable : false
    }
  }

  func windowNumber(of element: AXUIElement) -> CGWindowID? {
    let key = Self.key(of: element)
    return lock.withLock {
      guard error(for: key) == nil, let id = Self.windowID(of: key), state.windows[id] != nil
      else { return nil }
      return id.rawValue
    }
  }

  func setAttributeValue(_ name: String, _ value: CFTypeRef, of element: AXUIElement) -> AXError {
    let key = Self.key(of: element)
    if let id = Self.windowID(of: key), let gate = lock.withLock({ state.gates[id] }) {
      gate.entered.signal()
      gate.open.wait()
    }
    return lock.withLock {
      if let error = error(for: key) { return error }
      if state.appWindows[key] != nil {
        if name == kAXFrontmostAttribute { state.frontmostRequests.append(key) }
        return .success
      }
      guard let id = Self.windowID(of: key), let window = state.windows[id] else {
        return .invalidUIElement
      }
      switch name {
      case kAXPositionAttribute:
        let origin = Self.point(value)
        state.windows[id]?.frame.origin = origin
        state.calls[id, default: []].append(.position(origin))
      case kAXSizeAttribute:
        let size = Self.size(value)
        state.windows[id]?.frame.size = CGSize(
          width: max(size.width, window.minimumSize.width),
          height: max(size.height, window.minimumSize.height))
        state.calls[id, default: []].append(.size(size))
      case kAXMainAttribute: state.calls[id, default: []].append(.main)
      case kAXFocusedAttribute: state.calls[id, default: []].append(.focused)
      default: return .attributeUnsupported
      }
      return .success
    }
  }

  func performAction(_ action: String, on element: AXUIElement) -> AXError {
    let key = Self.key(of: element)
    return lock.withLock {
      if key >= Self.closeButtonBase, action == kAXPressAction {
        state.calls[WindowID(UInt32(key - Self.closeButtonBase)), default: []].append(.pressClose)
        return .success
      }
      if let error = error(for: key) { return error }
      guard let id = Self.windowID(of: key), state.windows[id] != nil else {
        return .invalidUIElement
      }
      guard action == kAXRaiseAction else { return .actionUnsupported }
      state.calls[id, default: []].append(.raise)
      return .success
    }
  }

  @MainActor
  func createObserver(
    processID: pid_t, handler: @escaping @MainActor (String, AXUIElement) -> Void
  ) -> AXError {
    lock.withLock {
      if let refusals = state.observerRefusals[processID], refusals > 0 {
        state.observerRefusals[processID] = refusals - 1
        return .cannotComplete
      }
      state.handlers[processID] = handler
      return .success
    }
  }

  @MainActor
  func addNotification(_ name: String, to element: AXUIElement, of processID: pid_t) -> AXError {
    let key = Self.key(of: element)
    return lock.withLock {
      if let error = error(for: key) { return error }
      guard state.handlers[processID] != nil else { return .invalidUIElementObserver }
      let registration = Registration(app: processID, element: key, notification: name)
      return state.registered.insert(registration).inserted
        ? .success : .notificationAlreadyRegistered
    }
  }

  @MainActor
  func removeObserver(processID: pid_t) {
    lock.withLock {
      state.handlers[processID] = nil
      state.registered = state.registered.filter { $0.app != processID }
    }
  }

  // MARK: - Private

  /// The error the element's window or app answers with. Call with the lock held.
  private func error(for key: pid_t) -> AXError? {
    if let error = state.errors[key] { return error }
    guard let id = Self.windowID(of: key), let app = state.windows[id]?.app else { return nil }
    return state.isHidingWindows ? .invalidUIElement : state.errors[app]
  }
}

// MARK: - Notifications

extension FakeAXClient {
  /// Delivers the notification, if it is registered: a window notification on the window's
  /// element, an app notification on the app's. Returns whether it was delivered.
  @MainActor
  @discardableResult
  func post(_ notification: String, for id: UInt32, in app: pid_t) -> Bool {
    let element = Self.windowBase + pid_t(id)
    let target = AXBridge.appNotifications.contains(notification) ? app : element
    let handler = lock.withLock { () -> (@MainActor (String, AXUIElement) -> Void)? in
      let registration = Registration(app: app, element: target, notification: notification)
      return state.registered.contains(registration) ? state.handlers[app] : nil
    }
    handler?(notification, AXUIElementCreateApplication(element))
    return handler != nil
  }

  func element(of id: UInt32) -> AXUIElement { Self.element(of: WindowID(id)) }

  func isObserving(_ app: pid_t) -> Bool { lock.withLock { state.handlers[app] != nil } }
}

// MARK: - What was asked

extension FakeAXClient {
  func calls(on id: UInt32) -> [Call] { lock.withLock { state.calls[WindowID(id)] ?? [] } }

  func frame(of id: UInt32) -> CGRect? { lock.withLock { state.windows[WindowID(id)]?.frame } }

  var frontmostRequests: [pid_t] { lock.withLock { state.frontmostRequests } }

  func forgetCalls() {
    lock.withLock {
      state.calls = [:]
      state.frontmostRequests = []
    }
  }
}

extension FakeAXClient {
  private static func key(of element: AXUIElement) -> pid_t {
    var processID: pid_t = 0
    _ = AXUIElementGetPid(element, &processID)
    return processID
  }

  private static func element(of id: WindowID) -> AXUIElement {
    AXUIElementCreateApplication(windowBase + pid_t(id.rawValue))
  }

  private static func windowID(of key: pid_t) -> WindowID? {
    (windowBase..<closeButtonBase).contains(key) ? WindowID(UInt32(key - windowBase)) : nil
  }

  /// An attribute that can't be read, as `AXUIElementCopyMultipleAttributeValues` reports it.
  private static var missing: AnyObject {
    var error = AXError.noValue
    return AXValueCreate(.axError, &error)!
  }

  private static func value(attribute: String, of window: Window) -> AnyObject? {
    var origin = window.frame.origin
    var size = window.frame.size
    let button = { (button: WindowButtons) -> AnyObject? in
      window.buttons.contains(button) ? AXUIElementCreateApplication(1) : nil
    }
    let values: [String: AnyObject?] = [
      kAXPositionAttribute: AXValueCreate(.cgPoint, &origin),
      kAXSizeAttribute: AXValueCreate(.cgSize, &size),
      kAXRoleAttribute: window.role as AnyObject?,
      kAXSubroleAttribute: window.subrole as AnyObject?,
      kAXMinimizedAttribute: window.isMinimized as AnyObject,
      "AXFullScreen": false as AnyObject,
      kAXCloseButtonAttribute: button(.close),
      kAXMinimizeButtonAttribute: button(.minimize),
      kAXFullScreenButtonAttribute: button(.fullScreen),
    ]
    return values[attribute] ?? nil
  }

  private static func point(_ value: CFTypeRef) -> CGPoint {
    var point = CGPoint.zero
    AXValueGetValue(unsafeDowncast(value, to: AXValue.self), .cgPoint, &point)
    return point
  }

  private static func size(_ value: CFTypeRef) -> CGSize {
    var size = CGSize.zero
    AXValueGetValue(unsafeDowncast(value, to: AXValue.self), .cgSize, &size)
    return size
  }
}
