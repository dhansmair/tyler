import CoreGraphics
import TylerCore
import TylerServer
import TylerTestSupport

@testable import TylerPlatform

/// A `MacWindowSystem` over the fake clients, with the events it sent so far.
@MainActor
final class WindowSystemHarness {
  let accessibility = FakeAXClient()
  let workspace = FakeWorkspaceClient()
  let screenLock = FakeScreenLock()
  let clock = TestClock()
  let windowSystem: MacWindowSystem
  private var events: [WindowEvent] = []

  init() {
    windowSystem = MacWindowSystem(
      client: accessibility, workspace: workspace, clock: clock, screenLock: screenLock)
    let stream = windowSystem.events
    Task { [weak self] in
      for await event in stream { self?.events.append(event) }
    }
  }

  /// An app with windows, running before the window system starts.
  func addApp(_ processID: pid_t, name: String = "App", windows: [UInt32] = []) {
    workspace.add(processID, name: name)
    for id in windows { accessibility.addWindow(id: id, frame: Self.frame(of: id), in: processID) }
  }

  func start() async {
    windowSystem.start()
    await settle()
  }

  /// The events sent since the last call.
  func takeEvents() async -> [WindowEvent] {
    await settle()
    defer { events = [] }
    return events
  }

  /// A frame of its own for each window, so a test can tell them apart.
  static func frame(of id: UInt32) -> CGRect {
    CGRect(x: 100 * CGFloat(id), y: 50, width: 400, height: 300)
  }
}

extension [WindowEvent] {
  /// The windows created, by id.
  var created: [UInt32] {
    compactMap { if case .created(let info) = $0 { info.id.rawValue } else { nil } }
  }

  var destroyed: [UInt32] {
    compactMap { if case .destroyed(let id) = $0 { id.rawValue } else { nil } }
  }

  var updated: [WindowInfo] {
    compactMap { if case .updated(let info) = $0 { info } else { nil } }
  }

  var focused: [UInt32?] {
    reduce(into: []) { ids, event in
      if case .focused(let id) = event { ids.append(id?.rawValue) }
    }
  }
}

extension FakeAXClient {
  /// A window as the fake app holds it.
  struct Window {
    let app: pid_t
    var frame: CGRect
    var role: String? = "AXWindow"
    var subrole: String?
    var buttons: WindowButtons
    var isResizable: Bool
    var isMinimized = false
    var minimumSize = CGSize.zero
    var losesPosition = false

    mutating func write(_ origin: CGPoint) {
      if losesPosition {
        losesPosition = false
      } else {
        frame.origin = origin
      }
    }
  }
}
