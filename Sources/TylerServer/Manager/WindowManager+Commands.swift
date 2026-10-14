import TylerCore
import TylerProtocol

extension WindowManager {
  /// Every command that changes windows starts here: it ends any slide in progress (jumping to
  /// its final state) and forgets any mouse drag, then checks that tiling can run. Windows still
  /// on their way to another display are let go: a move the app refused is never reported, and
  /// the window then belongs where it is.
  func beginCommand() -> Response? {
    endInteraction()
    mover.letGoOfCrossings()
    guard state == .running else { return .error(Self.permissionMessage) }
    guard tilingEnabled else { return .error(Self.tilingOffMessage) }
    return nil
  }

  func handleTilingRequest(_ request: Request) -> Response {
    switch request {
    case .retile: retile()
    case .focus(let target): focus(target)
    case .swap(let target): swap(target)
    case .layout(let choice): setLayout(choice)
    case .size(let choice): setSize(choice)
    case .ratio(let delta): adjustRatio(by: delta)
    case .float(let mode): setFloat(mode)
    case .ping, .status, .list, .reload, .configGet, .configSet, .configEdit, .tiling, .close,
      .workspace,
      .moveToWorkspace, .display, .moveToDisplay, .moveWorkspaceToDisplay, .debugAt,
      .debugWindows:
      .error("not a tiling request")
    }
  }

  package func retile() -> Response {
    if let failure = beginCommand() { return failure }
    return respond { tilingController.retile(model: &model) }
  }

  package func focus(_ target: ListTarget) -> Response {
    if let failure = beginCommand() { return failure }
    return respond { () throws(Refusal) in try tilingController.focus(target, model: &model) }
  }

  package func swap(_ target: ListTarget) -> Response {
    if let failure = beginCommand() { return failure }
    return respond { () throws(Refusal) in try tilingController.swap(target, model: &model) }
  }

  package func setFloat(_ mode: FloatMode) -> Response {
    if let failure = beginCommand() { return failure }
    return respond { () throws(Refusal) in try tilingController.setFloat(mode, model: &model) }
  }

  package func setTiling(_ mode: TilingMode) -> Response {
    endInteraction()
    return respond { tilingController.setTiling(mode, model: &model) }
  }

  package func setLayout(_ choice: LayoutChoice) -> Response {
    if let failure = beginCommand() { return failure }
    return respond { layoutController.setLayout(choice, model: &model) }
  }

  package func adjustRatio(by delta: Double) -> Response {
    if let failure = beginCommand() { return failure }
    return respond { () throws(Refusal) in
      try layoutController.adjustRatio(by: delta, model: &model)
    }
  }

  package func setSize(_ choice: SizeChoice) -> Response {
    if let failure = beginCommand() { return failure }
    return respond { () throws(Refusal) in try layoutController.setSize(choice, model: &model) }
  }

  func handleWorkspaceRequest(_ request: Request) -> Response {
    switch request {
    case .workspace(let target): switchWorkspace(target)
    case .moveToWorkspace(let target, let follow): moveToWorkspace(target, follow: follow)
    case .ping, .status, .list, .reload, .configGet, .configSet, .configEdit, .tiling, .retile,
      .focus, .swap,
      .layout, .size, .ratio, .float, .close, .display, .moveToDisplay, .moveWorkspaceToDisplay,
      .debugAt,
      .debugWindows:
      .error("not a workspace request")
    }
  }

  package func switchWorkspace(_ target: WorkspaceTarget) -> Response {
    if let failure = beginCommand() { return failure }
    return respond { () throws(Refusal) in
      try workspaceController.switchWorkspace(target, model: &model)
    }
  }

  package func moveToWorkspace(_ target: WorkspaceTarget, follow: Bool) -> Response {
    if let failure = beginCommand() { return failure }
    return respond { () throws(Refusal) in
      try workspaceController.moveToWorkspace(target, follow: follow, model: &model)
    }
  }

  func handleDisplayRequest(_ request: Request) -> Response {
    switch request {
    case .display(let target): switchDisplay(target)
    case .moveToDisplay(let target, let follow): moveToDisplay(target, follow: follow)
    case .moveWorkspaceToDisplay(let target): moveWorkspaceToDisplay(target)
    case .ping, .status, .list, .reload, .configGet, .configSet, .configEdit, .tiling, .retile,
      .focus, .swap,
      .layout, .size, .ratio, .float, .close, .workspace, .moveToWorkspace, .debugAt,
      .debugWindows:
      .error("not a display request")
    }
  }

  package func switchDisplay(_ target: DisplayTarget) -> Response {
    if let failure = beginCommand() { return failure }
    return respond { () throws(Refusal) in
      try displayController.switchDisplay(target, model: &model)
    }
  }

  package func moveToDisplay(_ target: DisplayTarget, follow: Bool) -> Response {
    if let failure = beginCommand() { return failure }
    return respond { () throws(Refusal) in
      try displayController.moveToDisplay(target, follow: follow, model: &model)
    }
  }

  package func moveWorkspaceToDisplay(_ target: DisplayTarget) -> Response {
    if let failure = beginCommand() { return failure }
    run(SyncController(context: context).sync(model: &model).effects)
    return respond { () throws(Refusal) in
      try displayController.moveWorkspaceToDisplay(target, model: &model)
    }
  }

  package func windows() -> Response {
    guard state == .running else { return .error(Self.permissionMessage) }
    return .windows(displayController.windowList(model))
  }

  /// Closing a window isn't tiling, so it works with tiling off too.
  package func closeWindow() -> Response {
    guard state == .running else { return .error(Self.permissionMessage) }
    endInteraction()
    return respond { () throws(Refusal) in try tilingController.close() }
  }

  private var layoutController: LayoutController { LayoutController(context: context) }

  private var displayController: DisplayController { DisplayController(context: context) }

  var workspaceController: WorkspaceController { WorkspaceController(context: context) }

  var tilingController: TilingController { TilingController(context: context) }
}
