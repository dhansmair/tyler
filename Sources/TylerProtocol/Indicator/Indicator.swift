import CoreGraphics
import TylerConfig
import TylerCore

/// Shows the workspaces somewhere the user can see them (the menu bar). The manager calls `show`
/// whenever the snapshot changes, and once at the start.
@MainActor
package protocol Indicator: AnyObject {
  func show(_ snapshot: IndicatorSnapshot)
}
