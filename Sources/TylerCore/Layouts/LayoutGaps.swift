import CoreGraphics

/// The space around and between tiled windows, in points. The same for every workspace: it
/// comes from the config, so it is passed to a layout rather than stored in a workspace.
package struct LayoutGaps: Equatable, Sendable {
  /// Space between the layout area's edge and the windows.
  package let outer: CGFloat
  /// Space between neighbouring windows.
  package let inner: CGFloat

  package init(inner: CGFloat = 0, outer: CGFloat = 0) {
    self.inner = max(0, inner)
    self.outer = max(0, outer)
  }
}
