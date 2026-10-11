import AppKit
import TylerCore

/// Turns an `IndicatorMenu` into an `NSMenu` whose items send their requests through `perform`.
/// Each indicator owns one.
@MainActor
final class MenuBuilder: NSObject {
  private let perform: @MainActor (Request) -> Void
  /// The requests behind the last built menu's items, indexed by each item's `tag`.
  private var requests: [Request] = []

  init(perform: @escaping @MainActor (Request) -> Void) {
    self.perform = perform
    super.init()
  }

  func menu(for model: IndicatorMenu) -> NSMenu {
    let menu = NSMenu()
    requests = []
    for entry in model.items {
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
