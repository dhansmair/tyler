import TylerProtocol

/// What choosing a menu item does: send a request, as `tyler` would, or quit tylerd.
package enum MenuChoice: Equatable, Sendable {
  case request(Request)
  case quit
}
