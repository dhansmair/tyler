import AppKit
import TylerCore
import TylerProtocol

/// The text menu bar item: the workspace numbers with the current one in brackets and the
/// current layout's symbol, as `TextTitle` spells them. Its menu hands each choice to `perform`.
/// Hidden when `[indicators.text] enabled = false`.
@MainActor
package final class TextIndicator: Indicator {
  private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private let menuBuilder: MenuBuilder
  /// What the item shows now, so it is only redrawn when that changes (a change of focus or of
  /// the layout's ratio reaches every indicator, but doesn't show here).
  private var shown: (title: TextTitle, menu: IndicatorMenu)?

  package init(perform: @escaping @MainActor (MenuChoice) -> Void) {
    menuBuilder = MenuBuilder(perform: perform)
  }

  package func show(_ snapshot: IndicatorSnapshot) {
    let isEnabled = snapshot.settings.text.isEnabled
    if item.isVisible != isEnabled { item.isVisible = isEnabled }
    let title = TextTitle(snapshot)
    let menu = IndicatorMenu(snapshot)
    guard title != shown?.title || menu != shown?.menu else { return }
    shown = (title, menu)
    item.button?.attributedTitle = Self.attributedTitle(title)
    item.menu = menuBuilder.menu(for: menu)
  }

  private static func attributedTitle(_ title: TextTitle) -> NSAttributedString {
    let font = NSFont.menuBarFont(ofSize: 0)
    let attributed = NSMutableAttributedString()
    for part in title.parts {
      let color: NSColor = part.isFaint ? .tertiaryLabelColor : .labelColor
      attributed.append(
        NSAttributedString(string: part.text, attributes: [.font: font, .foregroundColor: color]))
    }
    return attributed
  }
}
