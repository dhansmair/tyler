import CoreGraphics
import TylerCore

/// Which display commands act on. Each returns whether that changed which display it is.
extension Model {
  @discardableResult
  mutating func focusDisplay(holding number: Int) -> Bool {
    guard let location = rows.location(ofNumber: number) else { return false }
    return focusDisplay(at: location.position)
  }

  /// The display of the window's workspace, or, for a window on no workspace (floated, a
  /// dialog), the display it is on.
  @discardableResult
  mutating func focusDisplay(of windowID: WindowID, in context: ControllerContext) -> Bool {
    if let location = rows.location(of: windowID) { return focusDisplay(at: location.position) }
    guard let frame = context.registry.window(withID: windowID)?.frame,
      let key = DisplayGeometry.display(containing: frame, in: context.displays)?.key,
      let position = rows.position(of: key)
    else { return false }
    return focusDisplay(at: position)
  }

  @discardableResult
  mutating func focusDisplay(under location: CGPoint, in context: ControllerContext) -> Bool {
    guard let key = context.displays.first(where: { $0.frame.contains(location) })?.key,
      let position = rows.position(of: key)
    else { return false }
    return focusDisplay(at: position)
  }

  @discardableResult
  mutating func focusDisplay(at position: Int) -> Bool {
    let key = rows.entries[position].key
    guard key != rows.focusedKey else { return false }
    rows.focus(key)
    return true
  }

  mutating func recordFocus(_ windowID: WindowID) {
    guard let location = rows.location(of: windowID) else { return }
    rows[location.position].setFocus(windowID)
  }
}
