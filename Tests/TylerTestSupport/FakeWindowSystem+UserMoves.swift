import CoreGraphics
import TylerCore

@testable import TylerServer

extension FakeWindowSystem {
  package func frame(of windowID: UInt32) -> CGRect? {
    windows.first { $0.id.rawValue == windowID }?.frame
  }

  /// The user moves or resizes `windowID` to `frame`: the app moves it and reports the new frame.
  /// A window the backend doesn't have is a mistake in the test, not something to check.
  package func userMoves(_ windowID: UInt32, to frame: CGRect) async {
    guard let index = windows.firstIndex(where: { $0.id.rawValue == windowID }) else {
      preconditionFailure("no window \(windowID)")
    }
    windows[index].frame = frame
    send(.updated(windows[index]))
    await settle()
  }
}
