import AppKit

/// What `NSRunningApplication` says about an app.
struct RunningApp: Equatable, Sendable {
  let processID: pid_t
  let activationPolicy: NSApplication.ActivationPolicy
  let name: String?
  let bundleID: String?
}
