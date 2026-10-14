import AppKit
import TylerRuntime

/// Looks up what the map's windows show, each once: app icons, SF Symbols and glyphs. Entries no
/// window on the map uses any more are forgotten. A symbol, font or glyph that can't be found is
/// logged once, and its windows show the app's icon.
@MainActor
final class IconCache {
  private static let log = TylerLog(category: "indicator")
  /// The size glyph outlines are taken at; they are scaled to fit when drawn.
  private static let glyphSize: CGFloat = 64

  private var apps: [Int32: NSImage] = [:]
  /// `nil` for a name macOS doesn't know.
  private var symbols: [String: NSImage?] = [:]
  /// `nil` for a character the font has no glyph for.
  private var glyphs: [Character: CGPath?] = [:]
  /// The font the glyphs were taken from, by the name the config file gives; `.some(nil)` if
  /// no such font is installed.
  private var glyphFont: (name: String, font: CTFont?)?

  func icons(for map: WorkspaceMap) -> MapIcons {
    let windows = map.thumbnails.flatMap(\.windows)
    var names: Set<String> = []
    var characters: Set<Character> = []
    for icon in windows.compactMap(\.customIcon) {
      switch icon {
      case .symbol(let name): names.insert(name)
      case .glyph(let character): characters.insert(character)
      }
    }
    return MapIcons(
      apps: apps(for: Set(windows.compactMap(\.processID))),
      symbols: symbols(for: names),
      glyphs: glyphs(for: characters, font: map.iconFont))
  }

  private func apps(for processIDs: Set<Int32>) -> [Int32: NSImage] {
    apps = apps.filter { processIDs.contains($0.key) }
    for processID in processIDs where apps[processID] == nil {
      apps[processID] = NSRunningApplication(processIdentifier: processID)?.icon
    }
    return apps
  }

  private func symbols(for names: Set<String>) -> [String: NSImage] {
    symbols = symbols.filter { names.contains($0.key) }
    for name in names where symbols[name] == nil {
      let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
      if image == nil { Self.log.warning("icon symbol not found - '\(name)'") }
      symbols[name] = .some(image)
    }
    return symbols.compactMapValues { $0 }
  }

  private func glyphs(for characters: Set<Character>, font name: String) -> [Character: CGPath] {
    guard !characters.isEmpty else { return [:] }
    if glyphFont?.name != name {
      let font = NSFont(name: name, size: Self.glyphSize)
      if font == nil { Self.log.warning("icon font not found - '\(name)'") }
      glyphFont = (name, font)
      glyphs = [:]
    }
    guard let font = glyphFont?.font else { return [:] }
    glyphs = glyphs.filter { characters.contains($0.key) }
    for character in characters where glyphs[character] == nil {
      let path = Self.outline(of: character, in: font)
      if path == nil {
        Self.log.warning(
          "icon glyph not found - '\(name)' - \(Self.codePoints(character))"
        )
      }
      glyphs[character] = .some(path)
    }
    return glyphs.compactMapValues { $0 }
  }

  /// The outline of `character`'s glyph, or `nil` if the font has none (or it is blank).
  private static func outline(of character: Character, in font: CTFont) -> CGPath? {
    var units = Array(String(character).utf16)
    var glyphs = [CGGlyph](repeating: 0, count: units.count)
    guard CTFontGetGlyphsForCharacters(font, &units, &glyphs, units.count), glyphs[0] != 0,
      let path = CTFontCreatePathForGlyph(font, glyphs[0], nil), !path.boundingBoxOfPath.isEmpty
    else { return nil }
    return path
  }

  /// `U+F0239`, for the log.
  private static func codePoints(_ character: Character) -> String {
    character.unicodeScalars.map { "U+" + String($0.value, radix: 16, uppercase: true) }
      .joined(separator: " ")
  }
}
