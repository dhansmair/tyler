/// How much of the display a window takes in the strip layout.
package enum WindowSize: String, Codable, CaseIterable, Sendable {
  /// Half the width and the full height. New windows start like this, so two windows side by
  /// side look like `tall`.
  case half
  /// The full width and height.
  case full
  /// Half the width and half the height. Two in a row share a column, one above the other; one
  /// on its own fills its column like `half`.
  case quarter

  /// The size after this one, in declaration order, wrapping around.
  package var next: WindowSize {
    let all = Self.allCases
    guard let index = all.firstIndex(of: self) else { return self }
    return all[(index + 1) % all.count]
  }
}
