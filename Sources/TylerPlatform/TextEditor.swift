import Foundation

/// Opens a file in the user's editor: `command` if it is set, else `$VISUAL` or `$EDITOR` in
/// Terminal, else the default text editor.
package enum TextEditor {
  /// Creates the file first if it is missing: an editor may refuse a path that doesn't exist, and
  /// the config file is optional. Returns once the editor is launched, without waiting for it.
  package static func open(_ path: String, command: String) throws {
    let files = FileManager.default
    if !files.fileExists(atPath: path) {
      let directory = (path as NSString).deletingLastPathComponent
      try files.createDirectory(atPath: directory, withIntermediateDirectories: true)
      try Data().write(to: URL(fileURLWithPath: path))
    }
    let script = command.isEmpty ? fromEnvironment : command + #" "$1""#
    try Process.run(URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", script, "sh", path])
  }

  /// tylerd started at login doesn't have the variables a shell's startup files set, so the login
  /// shell is asked for them; it runs in the background, so a slow one doesn't hold tylerd up.
  /// `$VISUAL` and `$EDITOR` usually name a terminal editor, which needs a terminal to run in.
  /// `open -t` is the default text editor rather than the file type's handler: a `.toml` file
  /// often has none, or an IDE.
  private static let fromEnvironment = #"""
    editor="${VISUAL:-$EDITOR}"
    if [ -z "$editor" ] && [ -n "$SHELL" ]; then
      editor=$("$SHELL" -lic 'echo "$VISUAL"; echo "$EDITOR"' </dev/null 2>/dev/null \
        | tail -n 2 | grep -m 1 .)
    fi
    if [ -z "$editor" ]; then exec open -t "$1"; fi
    quoted="'$(printf '%s' "$1" | sed "s/'/'\\\\''/g")'"
    exec osascript -e 'on run argv' -e 'tell application "Terminal"' -e 'activate' \
      -e 'do script (item 1 of argv)' -e 'end tell' -e 'end run' "$editor $quoted"
    """#
}
