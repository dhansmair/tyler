import CoreGraphics
import TylerServer

@MainActor
package final class MacScreenLock: ScreenLock {
  package init() {}

  package var isLocked: Bool {
    guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
    return session["CGSSessionScreenIsLocked"] as? Bool ?? false
  }
}
