import CoreGraphics

/// Every window gets the whole area. The focused window is the one you see, because focusing
/// raises it.
package struct FullLayout: Layout {
  package init() {}

  package func frames(
    of windows: [WindowID], state: FullLayoutState, in area: CGRect, gaps: LayoutGaps
  ) -> [CGRect] {
    guard !windows.isEmpty else { return [] }
    let box = IntegerBox(area, inset: gaps.outer)
    return Array(repeating: box.rect, count: windows.count)
  }
}
