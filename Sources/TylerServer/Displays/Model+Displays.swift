import CoreGraphics
import TylerCore

/// Which display commands act on. Each returns whether that changed which display it is.
extension Model {
  @discardableResult
  mutating func focusDisplay(holding number: Int) -> Bool {
    guard let location = rows.location(ofNumber: number) else { return false }
    return focusDisplay(at: location.position)
  }

  @discardableResult
  mutating func focusDisplay(of windowID: WindowID, in context: ControllerContext) -> Bool {
    guard let position = displayPosition(of: windowID, in: context) else { return false }
    return focusDisplay(at: position)
  }

  /// The position of the display of the workspace the window is seen with, or, for a window on
  /// none (a dialog), of the display it is on.
  func displayPosition(of windowID: WindowID, in context: ControllerContext) -> Int? {
    if let location = rows.location(showing: windowID) { return location.position }
    guard let frame = context.registry.window(withID: windowID)?.frame,
      let key = DisplayGeometry.display(containing: frame, in: context.displays)?.key
    else { return nil }
    return rows.position(of: key)
  }

  @discardableResult
  mutating func focusDisplay(under location: CGPoint, in context: ControllerContext) -> Bool {
    guard let position = displayPosition(under: location, in: context) else { return false }
    return focusDisplay(at: position)
  }

  func displayPosition(under location: CGPoint, in context: ControllerContext) -> Int? {
    context.displays.first { $0.frame.contains(location) }.flatMap { rows.position(of: $0.key) }
  }

  @discardableResult
  mutating func focusDisplay(at position: Int) -> Bool {
    let key = rows.entries[position].key
    guard key != rows.focusedKey else { return false }
    rows.focus(key)
    return true
  }

  mutating func recordFocus(_ windowID: WindowID) {
    guard let location = rows.location(showing: windowID) else { return }
    rows[location.position].setFocus(windowID)
  }
}
