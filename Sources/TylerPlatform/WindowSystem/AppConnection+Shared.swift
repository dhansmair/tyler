import Foundation
import TylerServer

extension AppConnection {
  /// What every app's connection is given by the window system.
  struct Shared {
    let bridge: AXBridge
    let reader: WindowReader
    let clock: any Clock<Duration>
    let screenLock: any ScreenLock
  }
}
