/// Whether the screen is locked. While it is, the Accessibility API shows no windows (see
/// `devdocs/macos-behaviour.md`).
@MainActor
package protocol ScreenLock: AnyObject {
  var isLocked: Bool { get }
}
