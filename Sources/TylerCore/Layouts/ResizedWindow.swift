import CoreGraphics

package struct ResizedWindow: Equatable, Sendable {
  /// In the workspace's list.
  package let index: Int
  /// Where the user dragged the window's edges.
  package let frame: CGRect

  package init(index: Int, frame: CGRect) {
    self.index = index
    self.frame = frame
  }
}
