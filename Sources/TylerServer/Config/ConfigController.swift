import CoreGraphics
import TylerConfig
import TylerCore

/// Reading one setting, changing one until tylerd stops, and what a new config changes.
struct ConfigController {
  let context: ControllerContext

  /// A table of settings comes with its header, and no name gives the whole config.
  func value(_ name: String?) throws(Refusal) -> String {
    let config = context.config
    guard let name else { return TOML.write(config.document) }
    let path: [String]
    do {
      path = try Config.settingPath(name)
    } catch {
      throw .error(error.description)
    }
    guard let value = config.value(at: path) else {
      throw Config.isSetting(path)
        ? .error("\(name) is not set")
        : .error("unknown setting '\(name)' (`tyler config get` lists every setting)")
    }
    guard case .table(let table) = value else { return value.written }
    return TOML.write(table, at: path)
  }

  struct ChangedSetting {
    let config: Config
    /// As the config file writes it.
    let name: String
    let value: TOMLValue
  }

  /// The config with the setting called `name` changed to `text`, checked as the config file is.
  func setting(_ name: String, to text: String) throws(Refusal) -> ChangedSetting {
    do {
      let path = try Config.settingPath(name)
      let value = try Config.settingValue(text)
      return ChangedSetting(
        config: try context.config.setting(value, at: path), name: Config.settingName(path),
        value: value)
    } catch {
      throw .error("\(error) (the current settings stay)")
    }
  }

  /// `context.config` has just replaced `previous`: new workspaces start with its layout, the
  /// workspaces and the pointer follow it, and the current workspace re-tiles at once (the others
  /// pick the change up when they are shown). A new workspace count takes effect at once (see
  /// `WorkspaceRow.setCount`).
  func apply(replacing previous: Config, summary: String, model: inout Model) -> Decision {
    model.rows.newLayout = context.config.layouts.initial
    let configured = context.config.workspaceNumbers(displayCount: displayCount)
    if configured != previous.workspaceNumbers(displayCount: displayCount) {
      model.rows.setConfigured(configured)
    }
    var effects: [Effect] = context.isRunning ? [.applyPointerSettings] : []
    if context.isTiling(model) { effects.append(.reconcile()) }
    return Decision(summary, effects: effects)
  }

  private var displayCount: Int { max(1, context.displays.count) }
}
