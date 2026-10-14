import Foundation
import TylerCore

/// The config as a `tyler.toml` document: what `tyler config get` shows and `set` changes.
extension Config {
  /// Every setting as the file would set it, defaults included, so `parse(document:)` reads it
  /// back as this config. Only the apps and displays the config names have a table.
  package var document: [String: TOMLValue] {
    guard case .table(var document) = Section.document(self, Self.sections) else { return [:] }
    if !displays.isEmpty {
      document["displays"] = .table(
        Dictionary(
          uniqueKeysWithValues: displays.map { display, numbers in
            (String(display), Section.document(Display(workspaces: numbers), Display.settings))
          }))
    }
    if !apps.isEmpty {
      document["apps"] = .table(apps.mapValues { Section.document($0, App.settings) })
    }
    return document
  }
}

/// Reading and changing one setting by its dotted name, as `tyler config get|set` do.
extension Config {
  /// The parts of a setting's name, such as `gaps.inner` or `apps."com.mitchellh.ghostty".icon`.
  /// An app's name is in lower case, as the config keeps it.
  package static func settingPath(_ name: String) throws(ConfigError) -> [String] {
    var path: [String]
    do {
      path = try TOML.parseKey(name)
    } catch {
      throw .invalid("'\(name)' is not the name of a setting: \(error.message)")
    }
    if path.count > 1, path[0] == "apps" { path[1] = path[1].lowercased() }
    return path
  }

  /// A setting's name as the file writes it, quoted where it must be.
  package static func settingName(_ path: [String]) -> String {
    path.map(TOML.key).joined(separator: ".")
  }

  /// A value given on the command line: TOML (`5`, `true`, `"tall"`, `["tall", "full"]`), or a
  /// word without quotes, which is a string, so `tall` needs no shell quoting.
  package static func settingValue(_ text: String) throws(ConfigError) -> TOMLValue {
    do {
      return try TOML.parseValue(text)
    } catch {
      let trimmed = text.trimmingCharacters(in: .whitespaces)
      guard let first = trimmed.first, !"\"'[{".contains(first) else {
        throw .invalid("'\(text)' is not a value: \(error.message)")
      }
      return .string(trimmed)
    }
  }

  /// What the config sets at `path`: a value, or a table of them.
  package func value(at path: [String]) -> TOMLValue? {
    var value = TOMLValue.table(document)
    for part in path {
      guard case .table(let table) = value, let next = table[part] else { return nil }
      value = next
    }
    return value
  }

  /// Whether `path` names a setting or a table of them, set or not: `gaps`, `gaps.inner`,
  /// `apps.firefox` and `apps.firefox.icon` do, `gaps.middle` doesn't.
  package static func isSetting(_ path: [String]) -> Bool {
    settingNames.contains { name in
      let pattern = name.split(separator: ".")
      return path.count <= pattern.count
        && zip(path, pattern).allSatisfy { part, expected in expected == "*" || expected == part }
    }
  }

  /// This config with `value` at `path`, checked as the config file is checked, so the checks
  /// between settings (an app's workspace against the displays' lists) apply too.
  package func setting(_ value: TOMLValue, at path: [String]) throws(ConfigError) -> Config {
    var document = TOMLValue.table(document)
    try Self.set(value, at: path[...], in: &document, name: path)
    guard case .table(let table) = document else { return self }
    return try Self.parse(document: table)
  }

  private static func set(
    _ value: TOMLValue, at path: ArraySlice<String>, in document: inout TOMLValue, name: [String]
  ) throws(ConfigError) {
    guard let key = path.first else {
      document = value
      return
    }
    guard case .table(var table) = document else {
      let parent = settingName(Array(name.prefix(name.count - path.count)))
      throw .invalid("\(parent) is a value, not a table of settings")
    }
    var child = table[key] ?? .table([:])
    try set(value, at: path.dropFirst(), in: &child, name: name)
    table[key] = child
    document = .table(table)
  }
}
