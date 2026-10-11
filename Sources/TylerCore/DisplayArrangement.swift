import CoreGraphics

/// How the connected displays are numbered.
public enum DisplayArrangement {
  /// The displays in the order tyler numbers them, from 1: the primary display (the one with the
  /// menu bar, which comes first from the provider) and then the others left to right, then top
  /// to bottom. Displays at the same position go by id, so the order never depends on how
  /// macOS happens to list them.
  public static func ordered(_ displays: [DisplayInfo]) -> [DisplayInfo] {
    guard let primary = displays.first else { return [] }
    let others = displays.dropFirst().sorted {
      ($0.frame.minX, $0.frame.minY, $0.id) < ($1.frame.minX, $1.frame.minY, $1.id)
    }
    return [primary] + others
  }
}
