/// A value in a TOML document.
package enum TOMLValue: Equatable, Sendable {
  case string(String)
  case integer(Int)
  case float(Double)
  case boolean(Bool)
  case table([String: TOMLValue])
  case array([TOMLValue])
}
