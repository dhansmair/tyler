import Foundation

/// One of the event listeners tylerd keeps in macOS for `tyler status`: what it listens for,
/// whether macOS let it, and how often macOS turned it off since tylerd started.
package struct InputListener: Codable, Equatable, Sendable {
  package enum Kind: String, Codable, Sendable {
    case swipes
    case pointerMoves = "pointer moves"
    case modifierKey = "modifier key"
    case mouseButtons = "mouse buttons"
  }

  package var kind: Kind
  /// `false` when macOS refused to create it.
  package var isListening: Bool
  package var timesTurnedOff: Int
  package var lastTurnedOff: Date?

  package init(kind: Kind, isListening: Bool, timesTurnedOff: Int = 0, lastTurnedOff: Date? = nil) {
    self.kind = kind
    self.isListening = isListening
    self.timesTurnedOff = timesTurnedOff
    self.lastTurnedOff = lastTurnedOff
  }
}
