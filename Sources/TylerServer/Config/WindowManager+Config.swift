import CoreGraphics
import TylerConfig
import TylerCore
import TylerProtocol

/// The config commands. Reading the file is the manager's: it is input, not a decision.
extension WindowManager {
  func handleConfigRequest(_ request: Request) -> Response {
    switch request {
    case .reload: reload()
    case .configGet(let name): configValue(name)
    case .configSet(let name, let value): setConfig(name, to: value)
    case .ping, .status, .list, .configEdit, .tiling, .retile, .focus, .swap, .promote, .demote,
      .layout, .size,
      .ratio, .float,
      .close, .workspace, .moveToWorkspace, .display, .moveToDisplay, .moveWorkspaceToDisplay,
      .debugAt, .debugWindows:
      .error("not a config request")
    }
  }

  /// Reads the config file again and applies it, dropping what `setConfig` changed. A file that
  /// can't be used changes nothing, and no file at all means the defaults.
  package func reload() -> Response {
    guard let configSource else { return .error("tylerd was started without a config file") }
    let loaded: Config?
    do {
      loaded = try configSource.read()
    } catch {
      return .error("\(configSource.path): \(error) (the current settings stay)")
    }
    configChanges = []
    let summary =
      loaded == nil
      ? "no config file at \(configSource.path), using the defaults"
      : "reloaded \(configSource.path)"
    return apply(loaded ?? Config(), summary: summary)
  }

  package func configValue(_ name: String?) -> Response {
    do throws(Refusal) {
      return .message(try ConfigController(context: context).value(name))
    } catch {
      return Response(error)
    }
  }

  /// Until tylerd stops or the config is reloaded.
  package func setConfig(_ name: String, to text: String) -> Response {
    let changed: ConfigController.ChangedSetting
    do throws(Refusal) {
      changed = try ConfigController(context: context).setting(name, to: text)
    } catch {
      return Response(error)
    }
    if !configChanges.contains(changed.name) { configChanges.append(changed.name) }
    let until = "(until tylerd stops or `tyler config reload`)"
    return apply(changed.config, summary: "\(changed.name) = \(changed.value.written) \(until)")
  }

  /// A config change re-tiles, which a drag in progress would fight, so it ends whatever runs.
  private func apply(_ new: Config, summary: String) -> Response {
    endInteraction()
    let previous = config
    config = new
    return respond {
      ConfigController(context: context).apply(replacing: previous, summary: summary, model: &model)
    }
  }
}
