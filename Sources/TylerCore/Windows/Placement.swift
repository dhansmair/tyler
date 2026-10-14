import CoreGraphics

package struct Placement: Equatable, Sendable {
  package let id: WindowID
  package let frame: CGRect

  package init(id: WindowID, frame: CGRect) {
    self.id = id
    self.frame = frame
  }
}
