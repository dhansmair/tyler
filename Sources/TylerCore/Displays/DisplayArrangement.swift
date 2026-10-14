import CoreGraphics

/// How the connected displays are numbered.
package enum DisplayArrangement {
  /// The displays in the order tyler numbers them, from 1: the primary display (the one with the
  /// menu bar, which comes first from the provider) and then the others left to right, then top
  /// to bottom. Displays at the same position go by id, so the order never depends on how
  /// macOS happens to list them.
  package static func ordered(_ displays: [DisplayInfo]) -> [DisplayInfo] {
    guard let primary = displays.first else { return [] }
    let others = displays.dropFirst().sorted {
      ($0.frame.minX, $0.frame.minY, $0.id) < ($1.frame.minX, $1.frame.minY, $1.id)
    }
    return [primary] + others
  }

  /// The displays with their neighbours, the sides where another display lies beside them at
  /// the same height, and the edge each parks windows at: the right one, unless only that side
  /// has a neighbour, so parked windows never lie on another display. The middle display of
  /// three has neighbours on both sides and parks on the right.
  package static func sided(_ displays: [DisplayInfo]) -> [DisplayInfo] {
    displays.map { display in
      var sided = display
      let beside = displays.filter { $0.id != display.id && overlapsVertically($0, display) }
      if beside.contains(where: { $0.frame.minX >= display.frame.maxX - 1 }) {
        sided.neighbours.insert(.right)
      }
      if beside.contains(where: { $0.frame.maxX <= display.frame.minX + 1 }) {
        sided.neighbours.insert(.left)
      }
      sided.parkingEdge = sided.neighbours == [.right] ? .left : .right
      return sided
    }
  }

  /// Whether `other` reaches into the height where `display` shows windows.
  private static func overlapsVertically(_ other: DisplayInfo, _ display: DisplayInfo) -> Bool {
    other.frame.minY < display.visibleFrame.maxY && other.frame.maxY > display.visibleFrame.minY
  }
}
