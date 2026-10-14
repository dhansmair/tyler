extension Config {
  /// How the menu's Open config opens the config file.
  package struct Editor: Equatable, Sendable {
    /// A shell command the file's path is appended to, such as `open -na Ghostty --args -e nvim`.
    /// Empty runs `$VISUAL` or `$EDITOR` in Terminal, or else the default text editor.
    package var command: String

    package init(command: String = "") {
      self.command = command
    }
  }
}

extension Config.Editor {
  init(_ value: TOMLValue) throws(ConfigError) {
    self = try Section.read("editor", value, into: Self(), Self.settings)
  }

  /// The keys of `[editor]`, and how each is read.
  static let settings: [Setting<Self>] = [commandSetting]

  private static let commandSetting = Setting<Self>(
    "command",
    read: { editor, value, name throws(ConfigError) in
      guard case .string(let command) = value else {
        throw .invalid(
          "\(name) must be a shell command, such as \"open -na Ghostty --args -e nvim\"")
      }
      editor.command = command
    }, write: { .string($0.command) })
}
