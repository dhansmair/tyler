import Foundation

/// What `UnixSocket.readLineOrHangUp` found.
package enum LineRead: Equatable, Sendable {
  /// Up to the first `\n`, or what came before the peer closed.
  case line(Data)
  /// The peer closed without sending anything.
  case hungUp
  /// A read error, the receive timeout, or more than `maxBytes` without a newline.
  case failed
}
