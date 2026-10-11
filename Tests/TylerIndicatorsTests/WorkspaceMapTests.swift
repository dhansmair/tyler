import CoreGraphics
import Testing
import TylerCore

@testable import TylerIndicators

@Suite("Workspace map")
struct WorkspaceMapTests {
  /// A 16:10 display, so thumbnails are 22 by 14 points.
  private static let area = CGRect(x: 0, y: 25, width: 1600, height: 1000)

  private func map(
    counts: [Int] = [2, 1, 0, 0], current: Int = 0, layout: LayoutKind = .tall,
    area: CGRect? = WorkspaceMapTests.area, height: CGFloat = 14
  ) throws -> WorkspaceMap {
    try #require(
      WorkspaceMap(
        snapshot(counts: counts, current: current, layout: layout, area: area), height: height))
  }

  @Test(arguments: [area, nil])
  func thumbnailsHaveTheDisplaysShapeAndGapsBetweenThem(area: CGRect?) throws {
    let map = try map(area: area)
    #expect(map.thumbnails.map(\.frame.minX) == [0, 26, 52, 78])
    #expect(map.thumbnails.allSatisfy { $0.frame.size == CGSize(width: 22, height: 14) })
    #expect(map.size == CGSize(width: 100, height: 14))
  }

  @Test func aWideDisplayGivesWideThumbnails() throws {
    let map = try map(area: CGRect(x: 0, y: 0, width: 3440, height: 1440))
    #expect(map.thumbnails[0].frame.size == CGSize(width: 33, height: 14))
  }

  @Test func theHeightIsTheMenuBars() throws {
    let map = try map(height: 18)
    #expect(map.thumbnails[0].frame.size == CGSize(width: 29, height: 18))
    #expect(map.size == CGSize(width: 128, height: 18))
  }

  @Test func tenWorkspacesFitByGettingLower() throws {
    let map = try map(counts: Array(repeating: 1, count: 10), height: 18)
    #expect(map.size.width <= WorkspaceMap.maximumWidth)
    #expect(map.thumbnails[0].frame.size == CGSize(width: 22, height: 14))
  }

  @Test(arguments: [
    (1, [CGRect(x: 1, y: 1, width: 20, height: 12)]),
    (
      2,
      [CGRect(x: 1, y: 1, width: 10, height: 12), CGRect(x: 12, y: 1, width: 9, height: 12)]
    ),
    (
      3,
      [
        CGRect(x: 1, y: 1, width: 10, height: 12), CGRect(x: 12, y: 1, width: 9, height: 6),
        CGRect(x: 12, y: 8, width: 9, height: 5),
      ]
    ),
  ])
  func tallPlacesWindowsAsOnTheDisplay(count: Int, frames: [CGRect]) throws {
    #expect(try map(counts: [count]).thumbnails[0].windows.map(\.frame) == frames)
  }

  @Test func fullStacksEveryWindowInOneFrame() throws {
    let windows = try map(counts: [3], layout: .full).thumbnails[0].windows.map(\.frame)
    #expect(windows == Array(repeating: CGRect(x: 1, y: 1, width: 20, height: 12), count: 3))
  }

  @Test func theStripShowsOnlyTheWindowsInView() throws {
    let windows = try map(counts: [3], layout: .strip).thumbnails[0].windows.map(\.frame)
    #expect(windows.count == 2, "two half-width windows fill the view")
    #expect(windows.allSatisfy { CGRect(x: 0, y: 0, width: 22, height: 14).contains($0) })
  }

  @Test func windowsOnOtherWorkspacesSitInTheirThumbnail() throws {
    let second = try map().thumbnails[1]
    #expect(second.windows.map(\.frame) == [CGRect(x: 27, y: 1, width: 20, height: 12)])
  }

  @Test func everyRectIsInWholePoints() throws {
    var shifted = snapshot(counts: [3, 2], area: CGRect(x: 0, y: 0, width: 1512, height: 945))
    shifted.row.current.adjustRatio(by: 0.13)
    let map = try #require(WorkspaceMap(shifted, height: 14))
    let edges = map.thumbnails.flatMap(\.windows).map(\.frame).flatMap {
      [$0.minX, $0.minY, $0.maxX, $0.maxY]
    }
    #expect(edges.allSatisfy { $0 == $0.rounded() })
  }

  @Test func theRatioMovesTheWindows() throws {
    var wider = snapshot(counts: [2], area: Self.area)
    wider.row.current.adjustRatio(by: 0.2)
    let before = try map(counts: [2]).thumbnails[0].windows.map(\.frame)
    let after = try #require(WorkspaceMap(wider, height: 14)).thumbnails[0].windows.map(\.frame)
    #expect(after[0].width > before[0].width)
  }

  @Test func onlyTheCurrentWorkspaceShowsFocus() throws {
    var focused = snapshot(counts: [2, 2], current: 1, area: Self.area)
    focused.row[0].focus(.next)
    focused.row[1].focus(.prev)
    let map = try #require(WorkspaceMap(focused, height: 14))
    #expect(map.thumbnails.map(\.focusedIndex) == [nil, 1])
  }

  @Test(arguments: [(0, [1, 2, 0]), (1, [0, 2, 1]), (2, [0, 1, 2])])
  func theFocusedWindowIsDrawnLast(focused: Int, order: [Int]) throws {
    var full = snapshot(counts: [3], layout: .full, area: Self.area)
    for _ in 0...focused { full.row.current.focus(.next) }
    let thumbnail = try #require(WorkspaceMap(full, height: 14)).thumbnails[0]
    #expect(thumbnail.drawingOrder == order)
  }

  @Test func withoutFocusWindowsAreDrawnInListOrder() throws {
    #expect(try map(counts: [3]).thumbnails[0].drawingOrder == [0, 1, 2])
  }

  @Test func eachWindowKnowsItsAppsProcess() throws {
    var apps = snapshot(counts: [2, 1], area: Self.area)
    apps.apps = [WindowID(1): firefox, WindowID(3): ghostty]
    let map = try #require(WorkspaceMap(apps, height: 14))
    #expect(map.thumbnails.map { $0.windows.map(\.processID) } == [[101, nil], [303]])
    #expect(map.thumbnails.flatMap(\.windows).allSatisfy { $0.customIcon == nil })
  }

  @Test func theConfigFileCanSetAnIconByNameOrBundleID() throws {
    var apps = snapshot(counts: [3], area: Self.area)
    apps.apps = [WindowID(1): firefox, WindowID(2): ghostty, WindowID(3): other]
    apps.settings.icons = [
      "firefox": .glyph("\u{F0239}"), "com.mitchellh.ghostty": .symbol("terminal"),
    ]
    let windows = try #require(WorkspaceMap(apps, height: 14)).thumbnails[0].windows
    #expect(windows.map(\.customIcon) == [.glyph("\u{F0239}"), .symbol("terminal"), nil])
    #expect(windows.map(\.processID) == [101, 303, 505], "the app icon stays as the fallback")
  }

  @Test(arguments: [
    (CGRect(x: 0, y: 0, width: 34, height: 20), CGRect(x: 9, y: 2, width: 16, height: 16)),
    (CGRect(x: 1, y: 1, width: 15, height: 20), CGRect(x: 3, y: 5, width: 11, height: 11)),
    (CGRect(x: 10, y: 4, width: 12, height: 12), CGRect(x: 12, y: 6, width: 8, height: 8)),
  ])
  func theIconIsCentredAsLargeAsFits(window: CGRect, icon: CGRect) {
    #expect(WorkspaceMap.Window(frame: window).iconFrame == icon)
  }

  @Test func aWindowTooSmallShowsNoIcon() {
    #expect(WorkspaceMap.Window(frame: CGRect(x: 0, y: 0, width: 30, height: 11)).iconFrame == nil)
  }

  @Test func changingTheIconFontChangesTheMap() throws {
    var other = snapshot()
    other.settings.iconFont = "Hack Nerd Font"
    #expect(WorkspaceMap(other, height: 14) != WorkspaceMap(snapshot(), height: 14))
  }

  @Test func theConfigFileCanTurnTheIconsOff() throws {
    var plain = snapshot(counts: [2], area: Self.area)
    plain.apps = [WindowID(1): firefox, WindowID(2): ghostty]
    plain.settings.showsIcons = false
    plain.settings.icons = ["firefox": .symbol("globe")]
    let map = try #require(WorkspaceMap(plain, height: 14))
    #expect(map.thumbnails[0].windows == map.thumbnails[0].windows.map { .init(frame: $0.frame) })
  }

  @Test func itMarksTheCurrentAndEmptyWorkspaces() throws {
    let map = try map(counts: [2, 0, 1], current: 1)
    #expect(map.thumbnails.map(\.isCurrent) == [false, true, false])
    #expect(map.thumbnails.map(\.isEmpty) == [false, true, false])
  }

  @Test func theConfigFileCanTurnTheMapOff() {
    var off = snapshot()
    off.settings.map = false
    #expect(WorkspaceMap(off, height: 14) == nil)
  }

  @Test(arguments: [ServerStatus.Tiling.off, .waitingForPermission])
  func withoutTilingThereIsNoMap(tiling: ServerStatus.Tiling) {
    #expect(WorkspaceMap(snapshot(tiling: tiling), height: 14) == nil)
  }

  @Test(arguments: [
    (0, 0), (10, 0), (22, 0), (23, 0), (25, 1), (26, 1), (99, 3), (100, 3),
  ])
  func aPointPicksTheNearestThumbnail(offset: CGFloat, index: Int) throws {
    #expect(try map().workspaceIndex(at: CGPoint(x: offset, y: 7)) == index)
  }

  @Test(arguments: [-0.5, 100.5])
  func aPointBesideTheMapPicksNone(offset: CGFloat) throws {
    #expect(try map().workspaceIndex(at: CGPoint(x: offset, y: 7)) == nil)
  }

  @Test func theHeightOfAPointDoesNotMatter() throws {
    #expect(try map().workspaceIndex(at: CGPoint(x: 30, y: -4)) == 1)
  }
}

private let firefox = IndicatorSnapshot.App(
  processID: 101, name: "Firefox", bundleID: "org.mozilla.firefox")
private let ghostty = IndicatorSnapshot.App(
  processID: 303, name: "Ghostty", bundleID: "com.mitchellh.ghostty")
private let other = IndicatorSnapshot.App(processID: 505, name: "Other")
