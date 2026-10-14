/// The topmost on-screen window under the pointer, as the window server stacks them.
package struct StackedWindow: Codable, Equatable, Sendable {
  package let id: WindowID
  /// The window server's layer: 0 for normal windows; menus, the Dock and the menu bar sit
  /// higher.
  package let layer: Int
  /// The name of the app or process that owns it ("Window Server" for the cursor), so `tyler
  /// debug at` can say what a window tylerd doesn't track is.
  package let owner: String?

  package init(id: WindowID, layer: Int, owner: String? = nil) {
    self.id = id
    self.layer = layer
    self.owner = owner
  }

  /// How the log names it: `#3 (Window Server)` by its owner, or `#3` when that isn't known. A
  /// window tylerd tracks is named by `WindowInfo.logName` instead.
  package var logName: String {
    owner.map { "#\(id.rawValue) (\($0))" } ?? "#\(id.rawValue)"
  }
}
