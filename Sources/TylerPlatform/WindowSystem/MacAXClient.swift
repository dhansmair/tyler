import ApplicationServices
import Foundation

// Private but long-standing API (used by every macOS window manager) that maps an Accessibility
// element to its `CGWindowID`. It needs no special permission.
@_silgen_name("_AXUIElementGetWindow")
private func axGetWindow(
  _ element: AXUIElement,
  _ windowID: UnsafeMutablePointer<CGWindowID>
) -> AXError

/// The real `AXClient`. Each app's `AXObserver` delivers on the main run loop.
struct MacAXClient: AXClient {
  private let observers = Observers()

  func createApplication(_ processID: pid_t) -> AXUIElement {
    AXUIElementCreateApplication(processID)
  }

  func createSystemWide() -> AXUIElement { AXUIElementCreateSystemWide() }

  func setMessagingTimeout(_ seconds: Float, of element: AXUIElement) -> AXError {
    AXUIElementSetMessagingTimeout(element, seconds)
  }

  func copyAttributeValue(_ attribute: String, of element: AXUIElement) -> CFTypeRef? {
    var result: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success
    else { return nil }
    return result
  }

  func copyAttributeValues(_ attributes: [String], of element: AXUIElement) -> [AnyObject]? {
    var result: CFArray?
    let status = AXUIElementCopyMultipleAttributeValues(
      element, attributes as CFArray, AXCopyMultipleAttributeOptions(rawValue: 0), &result)
    guard status == .success else { return nil }
    return result as [AnyObject]?
  }

  func windowNumber(of element: AXUIElement) -> CGWindowID? {
    var raw = CGWindowID(0)
    guard axGetWindow(element, &raw) == .success else { return nil }
    return raw
  }

  func setAttributeValue(_ name: String, _ value: CFTypeRef, of element: AXUIElement) -> AXError {
    AXUIElementSetAttributeValue(element, name as CFString, value)
  }

  func performAction(_ action: String, on element: AXUIElement) -> AXError {
    AXUIElementPerformAction(element, action as CFString)
  }

  @MainActor
  func createObserver(
    processID: pid_t, handler: @escaping @MainActor (String, AXUIElement) -> Void
  ) -> AXError {
    observers.create(processID: processID, handler: handler)
  }

  @MainActor
  func addNotification(_ name: String, to element: AXUIElement, of processID: pid_t) -> AXError {
    observers.add(name, to: element, of: processID)
  }

  @MainActor func removeObserver(processID: pid_t) { observers.remove(processID: processID) }
}

extension MacAXClient {
  /// The observer of each app, kept alive here while its notifications are wanted.
  @MainActor
  private final class Observers {
    private var registrations: [pid_t: Registration] = [:]

    nonisolated init() {}

    func create(
      processID: pid_t, handler: @escaping @MainActor (String, AXUIElement) -> Void
    ) -> AXError {
      remove(processID: processID)
      var created: AXObserver?
      let status = AXObserverCreate(processID, observerCallback, &created)
      guard status == .success, let created else { return status }
      registrations[processID] = Registration(observer: created, handler: handler)
      CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
      return .success
    }

    func add(_ name: String, to element: AXUIElement, of processID: pid_t) -> AXError {
      guard let registration = registrations[processID] else { return .invalidUIElementObserver }
      let refcon = Unmanaged.passUnretained(registration).toOpaque()
      return AXObserverAddNotification(
        registration.observer, element, name as CFString, refcon)
    }

    func remove(processID: pid_t) {
      guard let registration = registrations.removeValue(forKey: processID) else { return }
      registration.isRunning = false
      CFRunLoopRemoveSource(
        CFRunLoopGetMain(), AXObserverGetRunLoopSource(registration.observer), .defaultMode)
    }
  }

  @MainActor
  fileprivate final class Registration {
    let observer: AXObserver
    let handler: @MainActor (String, AXUIElement) -> Void
    var isRunning = true

    init(observer: AXObserver, handler: @escaping @MainActor (String, AXUIElement) -> Void) {
      self.observer = observer
      self.handler = handler
    }

    func deliver(_ notification: String, from element: AXUIElement) {
      guard isRunning else { return }
      handler(notification, element)
    }
  }
}

/// The C callback. Because the observer's run loop source lives on the main run loop, this is
/// always called on the main thread, which is what makes `assumeIsolated` safe.
private let observerCallback: AXObserverCallback = { _, element, notification, refcon in
  guard let refcon else { return }
  let name = notification as String
  let registration = Unmanaged<MacAXClient.Registration>.fromOpaque(refcon).takeUnretainedValue()
  // `nonisolated(unsafe)`: AXUIElement isn't Sendable, but this callback already runs on the main
  // thread (the observer's run loop source is on the main run loop), so the element never
  // actually crosses a thread boundary.
  nonisolated(unsafe) let sourceElement = element
  MainActor.assumeIsolated {
    registration.deliver(name, from: sourceElement)
  }
}
