import CoreGraphics
import TylerCore

/// The map item's picture: one thumbnail per workspace, side by side, each with a rectangle for
/// every tiled window in view, placed as its layout places it. Coordinates are in points with the
/// origin at the top left, like the windows' own frames. Every rect is in whole points (the
/// thumbnails are, and the layouts split them in whole points), so the map only changes, and
/// redraws, when it visibly changes.
struct WorkspaceMap: Equatable, Sendable {
  /// One window in a thumbnail.
  struct Window: Equatable, Sendable {
    /// The largest an app icon is drawn, and the smallest: a window too small for that shows
    /// none.
    static let iconSizes: ClosedRange<CGFloat> = 8...16
    /// The least space between the icon and the window's edges.
    static let iconMargin: CGFloat = 2

    var frame: CGRect
    /// Its app's process, for the app's icon; `nil` if unknown.
    var processID: Int32?

    /// Where the app's icon goes: a square centred in the window, as large as fits within the
    /// margin and `iconSizes`, in whole points; `nil` when the window is too small for one.
    var iconFrame: CGRect? {
      let fitting = (min(frame.width, frame.height) - 2 * Self.iconMargin).rounded(.down)
      guard fitting >= Self.iconSizes.lowerBound else { return nil }
      let side = min(fitting, Self.iconSizes.upperBound)
      let origin = CGPoint(
        x: (frame.midX - side / 2).rounded(.down), y: (frame.midY - side / 2).rounded(.down))
      return CGRect(origin: origin, size: CGSize(width: side, height: side))
    }
  }

  /// One workspace.
  struct Thumbnail: Equatable, Sendable {
    var frame: CGRect
    /// The windows in view, in list order. In `full` they all share one frame.
    var windows: [Window]
    /// The focused window's index in `windows`; only on the current workspace.
    var focusedIndex: Int?
    var isCurrent: Bool

    var isEmpty: Bool { windows.isEmpty }

    /// The indices of `windows` in the order to draw them: the focused window last, so it shows
    /// on top where windows share a frame (in `full`).
    var drawingOrder: [Int] {
      let others = windows.indices.filter { $0 != focusedIndex }
      return focusedIndex.map { others + [$0] } ?? others
    }
  }

  static let spacing: CGFloat = 4
  /// The row's widest, reached with many workspaces; the thumbnails get lower to stay within it.
  static let maximumWidth: CGFloat = 260
  /// The display's aspect ratio when no display is known.
  static let defaultAspect: CGFloat = 16 / 10
  /// The gaps of a thumbnail's layout, so neighbouring windows stay apart.
  static let gaps = LayoutGaps(inner: 1, outer: 1)

  let size: CGSize
  let thumbnails: [Thumbnail]

  /// The map of `snapshot`'s row with thumbnails `height` points high, or `nil` when the config
  /// file turns the map off or tiling isn't running (windows then don't belong to workspaces, and
  /// there is nothing to map).
  init?(_ snapshot: IndicatorSnapshot, height: CGFloat) {
    guard snapshot.settings.map, snapshot.tiling == .on else { return nil }
    let row = snapshot.row
    let thumbnail = Self.thumbnailSize(count: row.count, height: height, area: snapshot.area)
    thumbnails = row.indices.map { index in
      let frame = CGRect(
        origin: CGPoint(x: CGFloat(index) * (thumbnail.width + Self.spacing), y: 0),
        size: thumbnail)
      let workspace = row[index]
      let placements = workspace.placements(in: frame, gaps: Self.gaps)
      let isCurrent = index == row.currentIndex
      return Thumbnail(
        frame: frame,
        windows: placements.map {
          Window(frame: $0.frame, processID: snapshot.processIDs[$0.id])
        },
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

  /// A thumbnail with the display's aspect ratio, `height` high (whole points), or lower if
  /// `count` of them wouldn't fit in `maximumWidth`.
  private static func thumbnailSize(count: Int, height: CGFloat, area: CGRect?) -> CGSize {
    let aspect = area.flatMap { $0.height > 0 ? $0.width / $0.height : nil } ?? defaultAspect
    let spacings = CGFloat(count - 1) * spacing
    let fitting = (maximumWidth - spacings) / (CGFloat(count) * aspect)
    let lower = min(height.rounded(.down), fitting.rounded(.down))
    return CGSize(width: (lower * aspect).rounded(), height: lower)
  }
}
