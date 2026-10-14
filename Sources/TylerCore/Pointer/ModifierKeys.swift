/// The modifier keys that, held with a mouse button, move or resize a window
/// (`[mouse] modifier`). The empty set turns moving and resizing with a modifier off.
package struct ModifierKeys: OptionSet, Hashable, Sendable {
  package let rawValue: Int

  package init(rawValue: Int) {
    self.rawValue = rawValue
  }

  package static let option = Self(rawValue: 1 << 0)
  package static let control = Self(rawValue: 1 << 1)
  package static let command = Self(rawValue: 1 << 2)
  package static let shift = Self(rawValue: 1 << 3)

  /// Each key with its name in the config, in the order `description` lists them.
  static let names: [(key: Self, name: String)] = [
    (.control, "ctrl"), (.option, "option"), (.command, "cmd"), (.shift, "shift"),
  ]

  /// Reads `none`, a key's name, or names joined by `+` (`ctrl+option`), in any order. Returns
  /// `nil` for an unknown or repeated name.
  package init?(parsing text: String) {
    if text == "none" {
      self = []
      return
    }
    var keys: Self = []
    for part in text.split(separator: "+", omittingEmptySubsequences: false) {
      guard let key = Self.names.first(where: { $0.name == part })?.key,
        !keys.contains(key)
      else { return nil }
      keys.insert(key)
    }
    self = keys
  }
}

extension ModifierKeys: CustomStringConvertible {
  /// The keys as the config writes them: `none`, or names joined by `+`.
  package var description: String {
    let held = Self.names.filter { contains($0.key) }.map(\.name)
    return held.isEmpty ? "none" : held.joined(separator: "+")
  }
}
