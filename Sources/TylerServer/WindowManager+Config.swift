import CoreGraphics
import TylerCore

/// The config file: applying it and reloading it.
extension WindowManager {
  /// Reads the config file again and applies it. The current workspace re-tiles at once; the
  /// others pick up the change when they are shown. A file that can't be used changes nothing,
  /// and no file at all means the defaults. A new workspace count takes effect at once (see
  /// `WorkspaceStack.setCount`).
  public func reload() -> Response {
    guard let configSource else { return .error("tylerd was started without a config file") }
    finishAnimation()
    let loaded: Config?
    do {
      loaded = try configSource.read()
    } catch {
      return .error("\(configSource.path): \(error) (the current settings stay)")
    }
    config = loaded ?? Config()
    applyWorkspaceCount()
    applyGaps()
    if state == .running { applyGestures() }
    let summary =
      loaded == nil
      ? "no config file at \(configSource.path), using the defaults"
      : "reloaded \(configSource.path)"
    guard isTiling else { return .message(summary) }
    let failures = applyLayout()
    guard failures > 0 else { return .message(summary) }
    return .message("\(summary); \(failures) window\(failures == 1 ? "" : "s") could not be placed")
  }

  /// Adds or removes workspaces to match the config. Windows of removed workspaces join the new
  /// last one; the caller re-tiles.
  private func applyWorkspaceCount() {
    guard workspaces.count != config.workspaces.count else { return }
    endDrag()
    workspaces.setCount(config.workspaces.count)
  }

  /// Gives every workspace the configured gaps; each keeps its own layout and ratio.
  func applyGaps() {
    workspaces.setGaps(inner: CGFloat(config.gaps.inner), outer: CGFloat(config.gaps.outer))
  }
}
