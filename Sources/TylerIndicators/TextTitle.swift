import TylerCore
import TylerProtocol

/// The text item's title: every workspace's number, from left to right, with the current one in
/// brackets and empty ones faint, then the layout's symbol, such as `1 [2] 3 4  ▥`. Exactly one
/// number is bracketed, so the title keeps its width while switching. Without tiling, windows
/// don't belong to workspaces, and a faint notice stands in for all of it.
struct TextTitle: Equatable, Sendable {
  /// One piece of the title. Faint pieces (empty workspaces, notices) are drawn in a dimmer
  /// colour.
  struct Part: Equatable, Sendable {
    var text: String
    var isFaint: Bool

    init(_ text: String, isFaint: Bool = false) {
      self.text = text
      self.isFaint = isFaint
    }
  }

  let parts: [Part]

  init(_ snapshot: IndicatorSnapshot) {
    if let notice = snapshot.notice {
      parts = [Part("tyler: \(notice)", isFaint: true)]
      return
    }
    let row = snapshot.row
    var parts: [Part] = []
    for index in row.indices {
      if index > 0 { parts.append(Part(" ")) }
      let number = String(row.number(at: index))
      parts.append(
        index == row.currentIndex
          ? Part("[\(number)]")
          : Part(number, isFaint: row[index].count == 0))
    }
    if let layout = snapshot.currentLayout { parts.append(Part("  \(layout.symbol)")) }
    self.parts = parts
  }
}

extension IndicatorSnapshot {
  /// The current workspace's layout, or `nil` when tiling isn't running.
  var currentLayout: LayoutKind? {
    tiling == .on ? row.current.layout : nil
  }

  /// Replaces the title when tiling isn't running.
  var notice: String? {
    switch tiling {
    case .on: nil
    case .off: "tiling off"
    case .waitingForPermission: "no access"
    }
  }
}
