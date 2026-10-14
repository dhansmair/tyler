import TylerCore

/// `[apps."<app>"]`: the settings of one app, named by its app name or bundle ID.
extension Config {
  /// What the config file sets for one app. Each setting is optional: an app's table only lists
  /// what it changes.
  package struct App: Equatable, Sendable {
    /// The number of the workspace the app's new windows open on.
    package var workspace: Int?
    /// What the map shows on the app's windows instead of its icon.
    package var icon: IndicatorIcon?

    package init(workspace: Int? = nil, icon: IndicatorIcon? = nil) {
      self.workspace = workspace
      self.icon = icon
    }
  }

  /// The 1-based workspace that new windows of this app are assigned to, if any.
  package func assignedWorkspace(bundleID: String?, appName: String) -> Int? {
    appSetting(\.workspace, bundleID: bundleID, appName: appName)
  }

  /// The icon the map shows on this app's windows instead of the app's icon, if any.
  package func icon(bundleID: String?, appName: String) -> IndicatorIcon? {
    appSetting(\.icon, bundleID: bundleID, appName: appName)
  }

  /// One setting of an app, from its table by bundle ID or by app name. The bundle ID's table wins
  /// where it sets the setting; both match regardless of case.
  private func appSetting<Value>(
    _ setting: KeyPath<App, Value?>, bundleID: String?, appName: String
  ) -> Value? {
    if let bundleID, let value = apps[bundleID.lowercased()]?[keyPath: setting] { return value }
    return apps[appName.lowercased()]?[keyPath: setting]
  }

  /// `[apps]`: a table per app, keyed by bundle ID or app name, which the result has in lower
  /// case. A workspace must be one a display lists, if any display lists its workspaces.
  static func apps(
    _ value: TOMLValue, displays: [Int: [Int]]
  ) throws(ConfigError) -> [String: App] {
    let keys = App.settings.map(\.key).joined(separator: " and ")
    guard case .table(let table) = value else {
      throw .invalid("apps must be a table: write [apps.<app>] and put \(keys) below it")
    }
    let listed = Set(displays.values.joined())
    var apps: [String: App] = [:]
    for (name, value) in table.sorted(by: { $0.key < $1.key }) {
      if case .table(let settings) = value, settings.values.contains(where: \.isTable) {
        throw .invalid(
          "apps.\(name) is a table of tables: quote app names and bundle IDs that contain dots,"
            + " like [apps.\"com.mitchellh.ghostty\"]")
      }
      let app = try Section.read("apps.\(name)", value, into: App(), App.settings)
      if let workspace = app.workspace, !listed.isEmpty, !listed.contains(workspace) {
        throw .invalid(
          "apps.\(name).workspace = \(workspace), but no display lists workspace \(workspace)")
      }
      guard apps.updateValue(app, forKey: name.lowercased()) == nil else {
        throw .invalid("apps.\(name) is set twice (app names and bundle IDs ignore case)")
      }
    }
    return apps
  }
}

extension Config.App {
  /// The keys of an app's table, and how each is read.
  static let settings: [Setting<Self>] = [
    Setting(
      "workspace",
      read: { app, value, name throws(ConfigError) in
        guard case .integer(let number) = value, Config.workspaceNumberRange.contains(number) else {
          let range = Config.workspaceNumberRange
          throw .invalid(
            "\(name) must be a workspace number, \(range.lowerBound) to \(range.upperBound)")
        }
        app.workspace = number
      }, write: { $0.workspace.map(TOMLValue.integer) }),
    Setting(
      "icon",
      read: { app, value, name throws(ConfigError) in
        guard case .string(let text) = value, let icon = IndicatorIcon(text) else {
          throw .invalid(
            "\(name) must be an SF Symbol's name, such as \"globe\", or one glyph, such as \"\\uf269\""
          )
        }
        app.icon = icon
      }, write: { $0.icon.map { .string($0.text) } }),
  ]
}
