import TylerProtocol

/// What choosing a menu item does: send a request, as `tyler` would, or act on tylerd itself.
package enum MenuChoice: Equatable, Sendable {
  case request(Request)
  case openConfig
  case quit
}
