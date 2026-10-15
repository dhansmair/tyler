import CoreGraphics

/// A part of a display, as fractions of its width and height from the top left: what a test
/// expects a window to fill, written down without asking the layout under test.
struct Region: Sendable {
  let across: ClosedRange<CGFloat>
  let down: ClosedRange<CGFloat>

  static let full = Region(across: 0...1, down: 0...1)
  static let leftHalf = Region(across: 0...0.5, down: 0...1)
  static let rightHalf = Region(across: 0.5...1, down: 0...1)
  static let leftTop = Region(across: 0...0.5, down: 0...0.5)
  static let leftBottom = Region(across: 0...0.5, down: 0.5...1)
  static let top = Region(across: 0...1, down: 0...0.5)
  static let bottom = Region(across: 0...1, down: 0.5...1)
  static let rightTop = Region(across: 0.5...1, down: 0...0.5)
  static let rightBottom = Region(across: 0.5...1, down: 0.5...1)

  /// The region of `area`, each edge rounded to a whole point.
  func rect(in area: CGRect) -> CGRect {
    let minX = (area.minX + area.width * across.lowerBound).rounded()
    let maxX = (area.minX + area.width * across.upperBound).rounded()
    let minY = (area.minY + area.height * down.lowerBound).rounded()
    let maxY = (area.minY + area.height * down.upperBound).rounded()
    return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
  }
}
