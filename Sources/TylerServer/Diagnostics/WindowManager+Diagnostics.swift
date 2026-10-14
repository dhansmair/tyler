import CoreGraphics
import TylerCore
import TylerProtocol

/// What tylerd sees and would do, for the `tyler debug` commands.
extension WindowManager {
  func handleDebugRequest(_ request: Request) -> Response {
    switch request {
    case .debugAt(let point): pointerDiagnosis(at: point)
    case .debugWindows: windowDrift()
    case .ping, .status, .list, .reload, .configGet, .configSet, .configEdit, .tiling, .retile,
      .focus, .swap,
      .layout, .size, .ratio, .float, .close, .workspace, .moveToWorkspace, .display,
      .moveToDisplay, .moveWorkspaceToDisplay:
      .error("not a debug request")
    }
  }

  /// Where tylerd's list of windows differs from what macOS reports now (`tyler debug windows`).
  /// It reads every window again but changes nothing.
  func windowDrift() -> Response {
    guard state == .running else { return .error(Self.permissionMessage) }
    let fresh = backend.freshWindows()
    var drift = WindowDrift.compare(believed: registry.windows, fresh: fresh)
    compareWorkspaceFocus(with: fresh.focusedID ?? registry.focusedID, in: &drift)
    return .drift(drift)
  }

  private func compareWorkspaceFocus(with focusedID: WindowID?, in drift: inout WindowDrift) {
    guard let focusedID, let window = registry.window(withID: focusedID),
      let location = rows.location(of: focusedID)
    else { return }
    let workspace = rows[location.position][location.index]
    drift.compareWorkspaceFocus(reported: window, recorded: workspace.focused)
  }

  /// What is at `point` and what tylerd would do there (`tyler debug at`).
  func pointerDiagnosis(at point: CGPoint?) -> Response {
    guard state == .running else { return .error(Self.permissionMessage) }
    guard let point else { return .error("debug at needs a point on screen") }
    guard let check = pointerCheck(at: point) else {
      return .error("tylerd can't read the window list, so it doesn't follow the pointer")
    }
    var diagnosis = PointerDiagnosis(point: point, check: check)
    let connected = connectedDisplays
    if let index = connected.firstIndex(where: { $0.frame.contains(point) }) {
      diagnosis.displayNumber = index + 1
      diagnosis.visibleFrame = connected[index].visibleFrame
    }
    if let topmost = check.topmost {
      var onTop = PointerDiagnosis.OnTop(id: topmost.id, layer: topmost.layer)
      let window = registry.window(withID: topmost.id)
      onTop.appName = window?.appName
      onTop.owner = topmost.owner
      onTop.title = window?.title
      onTop.workspace = rows.location(of: topmost.id).map { location in
        rows[location.position].number(at: location.index)
      }
      diagnosis.onTop = onTop
    }
    diagnosis.interaction = interaction.name
    diagnosis.modifier = config.mouse.modifier.description
    return .pointer(diagnosis)
  }
}
