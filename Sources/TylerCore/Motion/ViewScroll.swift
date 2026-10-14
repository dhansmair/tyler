import CoreGraphics

/// A trackpad swipe along a scrolling layout: the views it can rest at, worked out when the swipe
/// began, and the scroll between each pair of neighbouring views. Positions are in points from the
/// first view; the swipe's offset is in display widths, negative when the content moves left.
package struct ViewScroll: Equatable, Sendable {
  package let views: [Workspace.View]
  /// The view the swipe began at.
  package let startIndex: Int
  private let display: DisplayInfo

  /// `nil` with fewer than two views: then there is nowhere to scroll to.
  package init?(views: [Workspace.View], current: WindowID?, on display: DisplayInfo) {
    guard views.count > 1 else { return nil }
    self.views = views
    self.display = display
    startIndex = views.firstIndex { $0.firstVisible == current } ?? 0
  }

  /// The width of the view, in points: what an offset of one display width moves.
  package var viewWidth: CGFloat {
    display.visibleFrame.width
  }

  /// Where each view rests, left to right: the points a release can settle on.
  package var offsets: [CGFloat] {
    views.map(\.offset)
  }

  /// The position after the content moved by `offset` display widths, kept between the first
  /// and the last view.
  package func position(movedBy offset: Double) -> CGFloat {
    let moved = views[startIndex].offset - CGFloat(offset) * viewWidth
    return moved.clamped(to: offsets[0]...offsets[offsets.count - 1])
  }

  /// The pair of neighbouring views `position` lies between (`index` and `index + 1`), and how
  /// far along from the first it is.
  package func segment(at position: CGFloat) -> (index: Int, progress: Double) {
    let index = offsets.dropLast().lastIndex { $0 <= position } ?? 0
    let length = offsets[index + 1] - offsets[index]
    let progress = length > 0 ? Double((position - offsets[index]) / length) : 0
    return (index, progress.clamped(to: 0...1))
  }

  /// The scroll from view `index` to view `index + 1`.
  package func plan(forSegment index: Int) -> ScrollPlan {
    ScrollPlan(from: views[index].arrangement, to: views[index + 1].arrangement, on: display)
  }

  /// Where `windows` rest with view `index`: in their slots if in view, parked if not.
  package func resting(_ windows: Set<WindowID>, at index: Int) -> [Placement] {
    views[index].arrangement.filter { windows.contains($0.id) }.map { placement in
      display.shows(placement.frame)
        ? placement
        : Placement(id: placement.id, frame: Parking.frame(for: placement.frame, on: display))
    }
  }
}
