/// What macOS says about tylerd's access to windows, read before it starts tracking them.
package struct AccessFacts: Equatable, Sendable {
  /// How one Accessibility read that needs the permission went.
  package enum Probe: Equatable, Sendable {
    case allowed
    /// macOS refused it as if the permission were missing.
    case refused
    /// The app asked didn't answer; says nothing about the permission.
    case noAnswer
  }

  package var isTrusted: Bool
  package var probe: Probe
  package var isScreenLocked: Bool

  package init(isTrusted: Bool, probe: Probe, isScreenLocked: Bool) {
    self.isTrusted = isTrusted
    self.probe = probe
    self.isScreenLocked = isScreenLocked
  }
}
