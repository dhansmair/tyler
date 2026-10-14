import ApplicationServices
import TylerServer

extension WindowSystemError {
  /// Only the reason: the caller says what it asked for, of which window.
  init(refusal status: AXError) {
    self =
      status == .cannotComplete
      ? .refused("its app didn't answer") : .refused("AX error \(status.rawValue)")
  }
}
