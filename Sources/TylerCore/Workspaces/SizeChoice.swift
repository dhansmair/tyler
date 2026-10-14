/// Either one specific strip size or the next one in `WindowSize`'s order.
package enum SizeChoice: Codable, Equatable, Sendable {
  case set(WindowSize)
  case next
}
