import CoreGraphics
import TylerCore

/// The map item's picture: one thumbnail per workspace, side by side, each with a rectangle for
/// every tiled window in view, placed as its layout places it. Coordinates are in points with the
/// origin at the top left, like the windows' own frames. Every rect is in whole points (the
/// thumbnails are, and the layouts split them in whole points), so the map only changes, and
/// redraws, when it visibly changes.
struct WorkspaceMap: Equatable, Sendable {
  /// One workspace.
  struct Thumbnail: Equatable, Sendable {
    var frame: CGRect
    /// The windows in view, in list order. In `full` they all share one frame.
    var windows: [CGRect]
    /// The focused window's index in `windows`; only on the current workspace.
    var focusedIndex: Int?
    var isCurrent: Bool

    var isEmpty: Bool { windows.isEmpty }
  }

  static let height: CGFloat = 14
  static let spacing: CGFloat = 4
  /// The row's widest, reached with ten workspaces; the thumbnails get lower to stay within it.
  static let maximumWidth: CGFloat = 200
  /// The display's aspect ratio when no display is known.
  static let defaultAspect: CGFloat = 16 / 10
  /// The gaps of a thumbnail's layout, so neighbouring windows stay apart.
  static let gaps = LayoutGaps(inner: 1, outer: 1)

  let size: CGSize
  let thumbnails: [Thumbnail]

  /// The map of `snapshot`'s row, or `nil` while tiling isn't running: windows then don't belong
  /// to workspaces, and there is nothing to map.
  init?(_ snapshot: IndicatorSnapshot) {
    guard snapshot.tiling == .on else { return nil }
    let row = snapshot.row
    let thumbnail = Self.thumbnailSize(count: row.count, area: snapshot.area)
    thumbnails = row.indices.map { index in
      let frame = CGRect(
        origin: CGPoint(x: CGFloat(index) * (thumbnail.width + Self.spacing), y: 0),
        size: thumbnail)
      let workspace = row[index]
      let placements = workspace.placements(in: frame, gaps: Self.gaps)
      let isCurrent = index == row.currentIndex
      return Thumbnail(
        frame: frame,
        windows: placements.map(\.frame),
        focusedIndex: isCurrent ? placements.firstIndex { $0.id == workspace.focused } : nil,
        isCurrent: isCurrent)
    }
    let width = thumbnails.last?.frame.maxX ?? 0
    size = CGSize(width: width, height: thumbnail.height)
  }

  /// The index of the workspace whose thumbnail is at `point`'s `x`, whatever its `y` (the item
  /// is taller than the map). A point in a gap goes to the nearest thumbnail; one left or right
  /// of the map to none.
  func workspaceIndex(at point: CGPoint) -> Int? {
    guard point.x >= 0, point.x <= size.width else { return nil }
    return thumbnails.indices.min {
      distance(point.x, thumbnails[$0]) < distance(point.x, thumbnails[$1])
    }
  }

  private func distance(_ offset: CGFloat, _ thumbnail: Thumbnail) -> CGFloat {
    max(thumbnail.frame.minX - offset, 0, offset - thumbnail.frame.maxX)
  }

  /// A thumbnail with the display's aspect ratio, `height` high, or lower if `count` of them
  /// wouldn't fit in `maximumWidth`. Whole points.
  private static func thumbnailSize(count: Int, area: CGRect?) -> CGSize {
    let aspect = area.flatMap { $0.height > 0 ? $0.width / $0.height : nil } ?? defaultAspect
    let spacings = CGFloat(count - 1) * spacing
    let fitting = (maximumWidth - spacings) / (CGFloat(count) * aspect)
    let height = min(Self.height, fitting.rounded(.down))
    return CGSize(width: (height * aspect).rounded(), height: height)
  }
}
