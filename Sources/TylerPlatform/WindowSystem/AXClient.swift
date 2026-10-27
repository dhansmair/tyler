import ApplicationServices

/// The C Accessibility API that tylerd uses, one to one and nothing else, so the logic above it
/// can be tested against a fake. `Sendable`: the steps of a move are written from each app's own
/// queue.
///
/// The window system holds it as `any AXClient` although each step of a slide goes through it:
/// every call is a round trip to an app that takes milliseconds, so the dynamic dispatch is noise.
protocol AXClient: Sendable {
  func createApplication(_ processID: pid_t) -> AXUIElement
  func createSystemWide() -> AXUIElement
  func setMessagingTimeout(_ seconds: Float, of element: AXUIElement) -> AXError

  /// `nil` if the attribute couldn't be read.
  func copyAttributeValue(_ attribute: String, of element: AXUIElement) -> CFTypeRef?
  /// `nil` if the call failed; an attribute that couldn't be read is an `AXValue` holding its error.
  func copyAttributeValues(_ attributes: [String], of element: AXUIElement) -> [AnyObject]?
  /// `nil` if the call failed.
  func isAttributeSettable(_ attribute: String, of element: AXUIElement) -> Bool?
  /// `_AXUIElementGetWindow`; `nil` if the call failed.
  func windowNumber(of element: AXUIElement) -> CGWindowID?

  func setAttributeValue(_ name: String, _ value: CFTypeRef, of element: AXUIElement) -> AXError
  func performAction(_ action: String, on element: AXUIElement) -> AXError

  /// Creates the app's observer, delivering its notifications to `handler` on the main thread.
  @MainActor
  func createObserver(
    processID: pid_t, handler: @escaping @MainActor (String, AXUIElement) -> Void
  ) -> AXError
  @MainActor
  func addNotification(_ name: String, to element: AXUIElement, of processID: pid_t) -> AXError
  /// Stops the app's notifications; none is delivered after this returns.
  @MainActor func removeObserver(processID: pid_t)
}
