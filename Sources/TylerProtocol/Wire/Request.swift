import Foundation
import TylerCore

/// A command sent from the `tyler` client to the `tylerd` server.
package enum Request: Codable, Equatable, Sendable {
  case ping
  /// Asks the server about itself: pid, binary, config, tiling.
  case status
  case list
  /// Reads the config file again and applies it, dropping what `configSet` changed.
  case reload
  /// Asks for a setting, or a table of them, by its dotted name; `nil` asks for the whole config.
  case configGet(String?)
  /// Changes one setting until tylerd stops or the config is reloaded. The server parses both
  /// the name and the value, as the config file has them.
  case configSet(name: String, value: String)
  case retile
  case tiling(TilingMode)
  case focus(ListTarget)
  case swap(ListTarget)
  case layout(LayoutChoice)
  /// Sets the focused window's size in the strip layout.
  case size(SizeChoice)
  /// Changes the master column's share of the width by this amount.
  case ratio(Double)
  /// Floats the focused window (`on`), tiles it again (`off`), or switches between the two.
  case float(FloatMode)
  /// Closes the focused window, as its close button does: the app keeps running.
  case close
  /// Switches to another workspace.
  case workspace(WorkspaceTarget)
  /// Sends the focused window to another workspace; with `follow`, the view goes along.
  case moveToWorkspace(WorkspaceTarget, follow: Bool)
  /// Makes another display the focused one, focusing its current workspace.
  case display(DisplayTarget)
  /// Sends the focused window to another display's current workspace; with `follow`, the focus
  /// goes along.
  case moveToDisplay(DisplayTarget, follow: Bool)
  /// Moves the focused display's current workspace, with its windows, to another display.
  case moveWorkspaceToDisplay(DisplayTarget)
  /// Asks what tylerd sees and would do at a point on screen; `nil` until the client fills in
  /// where the pointer is.
  case debugAt(CGPoint?)
  /// Asks where tylerd's picture of the windows differs from what macOS reports right now.
  case debugWindows
}
