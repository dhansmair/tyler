/// Where `tyler config edit` opens the config file. A terminal editor needs the terminal the
/// command runs in; from a hotkey there is none, so tylerd opens it as the menu's Open config does.
package enum ConfigEditing: Equatable, Sendable {
  /// Run this editor command here, in the foreground.
  case inTerminal(editor: String)
  case byServer

  package static func choose(isTerminal: Bool, environment: [String: String]) -> Self {
    guard isTerminal,
      let editor = [environment["VISUAL"], environment["EDITOR"]]
        .compactMap({ $0 }).first(where: { !$0.isEmpty })
    else { return .byServer }
    return .inTerminal(editor: editor)
  }
}
