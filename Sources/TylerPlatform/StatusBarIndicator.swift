import AppKit
import TylerCore
import TylerServer

/// The menu bar item: the workspace numbers with the current one in brackets and the current
/// layout's symbol, as `IndicatorState.title` spells them. Its menu sends ordinary requests
/// through `perform`, the same ones `tyler` sends.
@MainActor
public final class StatusBarIndicator: NSObject, Indicator {
  private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private let perform: @MainActor (Request) -> Void
  /// The requests behind the current menu's items, indexed by each item's `tag`.
  private var requests: [Request] = []

  public init(perform: @escaping @MainActor (Request) -> Void) {
    self.perform = perform
    super.init()
  }

  public func show(_ state: IndicatorState) {
    item.button?.attributedTitle = Self.title(for: state)
    item.menu = menu(for: state)
  }

  private static func title(for state: IndicatorState) -> NSAttributedString {
    let font = NSFont.menuBarFont(ofSize: 0)
    let title = NSMutableAttributedString()
    for part in state.title {
      let color: NSColor = part.isFaint ? .tertiaryLabelColor : .labelColor
      title.append(
        NSAttributedString(string: part.text, attributes: [.font: font, .foregroundColor: color]))
    }
    return title
  }

  private func menu(for state: IndicatorState) -> NSMenu {
    let menu = NSMenu()
    requests = []
    for entry in state.menu {
      switch entry {
      case .action(let title, let isChecked, let request):
        let menuItem = NSMenuItem(title: title, action: #selector(choose(_:)), keyEquivalent: "")
        menuItem.target = self
        menuItem.state = isChecked ? .on : .off
        menuItem.tag = requests.count
        requests.append(request)
        menu.addItem(menuItem)
      case .note(let title):
        let menuItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        menuItem.isEnabled = false
        menu.addItem(menuItem)
      case .separator:
        menu.addItem(.separator())
      }
    }
    return menu
  }

  @objc private func choose(_ sender: NSMenuItem) {
    guard requests.indices.contains(sender.tag) else { return }
    perform(requests[sender.tag])
  }
}
