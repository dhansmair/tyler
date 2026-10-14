/// The buttons in a window's title bar, as its app reports them.
package struct WindowButtons: OptionSet, Sendable {
  package let rawValue: Int

  package init(rawValue: Int) {
    self.rawValue = rawValue
  }

  package static let close = WindowButtons(rawValue: 1 << 0)
  package static let minimize = WindowButtons(rawValue: 1 << 1)
  package static let fullScreen = WindowButtons(rawValue: 1 << 2)
  package static let all: WindowButtons = [.close, .minimize, .fullScreen]
}
