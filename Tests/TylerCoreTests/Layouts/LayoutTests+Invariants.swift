import CoreGraphics
import Testing

@testable import TylerCore

/// What every layout guarantees, whatever the count and the gaps: a new layout gets these checks
/// for free once it is a `LayoutKind`.
@Suite("Every layout")
struct LayoutInvariantsTests {
  private static let area = CGRect(x: 10, y: 30, width: 1000, height: 600)
  private static let display = DisplayInfo(id: 1, frame: area, visibleFrame: area)
  private static let gaps = [LayoutGaps(), LayoutGaps(inner: 8, outer: 12)]

  /// A workspace of `count` windows in `kind`, the last one focused.
  private func workspace(_ kind: LayoutKind, count: Int) -> Workspace {
    var workspace = Workspace(layout: kind)
    for raw in 0..<count { workspace.append(WindowID(UInt32(raw + 1))) }
    if count > 0 { workspace.setFocus(WindowID(UInt32(count))) }
    return workspace
  }

  @Test(arguments: LayoutKind.allCases, [0, 1, 2, 3, 5, 8])
  func everyWindowGetsOneFrameInListOrder(kind: LayoutKind, count: Int) {
    let workspace = workspace(kind, count: count)
    for gaps in Self.gaps {
      #expect(workspace.arrangement(in: Self.area, gaps: gaps).map(\.id) == workspace.windows)
    }
  }

  @Test(arguments: LayoutKind.allCases, [1, 2, 3, 5, 8])
  func windowsInViewLieInsideTheAreaWithoutOverlapping(kind: LayoutKind, count: Int) {
    let workspace = workspace(kind, count: count)
    for gaps in Self.gaps {
      let frames = workspace.placements(on: Self.display, gaps: gaps).map(\.frame)
      for frame in frames {
        #expect(Self.area.contains(frame), "\(frame) with gaps \(gaps)")
        #expect(frame.width > 0 && frame.height > 0, "\(frame) with gaps \(gaps)")
      }
      for (index, frame) in frames.enumerated() {
        for other in frames[(index + 1)...] {
          // `full` stacks its windows in one frame; any other two frames share at most an edge.
          let shared = frame.intersection(other)
          #expect(
            frame == other || shared.isNull || shared.width * shared.height < 1,
            "\(frame) and \(other) with gaps \(gaps)")
        }
      }
    }
  }

  @Test(arguments: LayoutKind.allCases, [1, 2, 3, 5, 8])
  func theFocusedWindowIsInView(kind: LayoutKind, count: Int) {
    let workspace = workspace(kind, count: count)
    for gaps in Self.gaps {
      let shown = workspace.placements(on: Self.display, gaps: gaps).map(\.id)
      #expect(shown.contains(WindowID(UInt32(count))))
      if kind != .strip {
        #expect(shown == workspace.windows, "only the strip has windows out of view")
      }
    }
  }
}
