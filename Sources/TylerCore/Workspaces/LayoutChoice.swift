/// Either one specific layout or the next one in `LayoutKind`'s order.
package enum LayoutChoice: Codable, Equatable, Sendable {
  case set(LayoutKind)
  case next
}
