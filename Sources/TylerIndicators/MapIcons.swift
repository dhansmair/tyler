import AppKit

/// What the map draws on its windows: app icons by process, SF Symbols by name, and glyph
/// outlines by character.
struct MapIcons {
  var apps: [Int32: NSImage] = [:]
  var symbols: [String: NSImage] = [:]
  /// In the glyph font's own coordinates: y up, at its design size.
  var glyphs: [Character: CGPath] = [:]
}
