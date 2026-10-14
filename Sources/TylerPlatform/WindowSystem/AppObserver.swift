import ApplicationServices
import Foundation

/// One `AXObserver` for one running app, delivering its notifications on the main run loop.
@MainActor
final class AppObserver {
  enum Failure: Error {
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

  typealias Handler = (_ notification: String, _ element: AXUIElement) -> Void

  let processID: pid_t
  private let observer: AXObserver
  private let handler: Handler
  private var isRunning = true

  /// Creates the observer and subscribes to the app-level notifications. Throws if the app
  /// refuses, which is common for an app that has only just launched; callers retry.
  init(processID: pid_t, applicationElement: AXUIElement, handler: @escaping Handler) throws {
    var created: AXObserver?
    let status = AXObserverCreate(processID, observerCallback, &created)
    guard status == .success, let created else { throw Failure.create(status) }

    self.processID = processID
    self.observer = created
    self.handler = handler

    CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
    do {
      for name in Self.appNotifications {
        try add(name, to: applicationElement)
      }
    } catch {
      stop()
      throw error
    }
  }

  /// Subscribes to the per-window notifications. Failures are reported but not fatal: a window
  /// that can't be observed is still listed, it just won't update live.
  @discardableResult
  func observe(window: AXUIElement) -> [Failure] {
    var failures: [Failure] = []
    for name in Self.windowNotifications {
      do {
        try add(name, to: window)
      } catch let failure as Failure {
        failures.append(failure)
      } catch {
        continue
      }
    }
    return failures
  }

  /// Stops delivery. After this the observer must be discarded.
  func stop() {
    guard isRunning else { return }
    isRunning = false
    CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
  }

  fileprivate func deliver(_ notification: String, from element: AXUIElement) {
    guard isRunning else { return }
    handler(notification, element)
  }

  private func add(_ name: String, to element: AXUIElement) throws {
    let refcon = Unmanaged.passUnretained(self).toOpaque()
    let status = AXObserverAddNotification(observer, element, name as CFString, refcon)
    // `notificationAlreadyRegistered` happens when a window is observed twice; harmless.
    guard status == .success || status == .notificationAlreadyRegistered else {
      throw Failure.register(name, status)
    }
  }
}

/// The C callback. Because the observer's run loop source lives on the main run loop, this is
/// always called on the main thread, which is what makes `assumeIsolated` safe.
private let observerCallback: AXObserverCallback = { _, element, notification, refcon in
  guard let refcon else { return }
  let name = notification as String
  let appObserver = Unmanaged<AppObserver>.fromOpaque(refcon).takeUnretainedValue()
  // `nonisolated(unsafe)`: AXUIElement isn't Sendable, but this callback already runs on the main
  // thread (the observer's run loop source is on the main run loop), so the element never
  // actually crosses a thread boundary.
  nonisolated(unsafe) let sourceElement = element
  MainActor.assumeIsolated {
    appObserver.deliver(name, from: sourceElement)
  }
}
