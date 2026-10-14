import AppKit
import TylerCore
import TylerProtocol

/// Turns an `IndicatorMenu` into an `NSMenu` whose items hand their choices to `perform`.
/// Each indicator owns one.
@MainActor
final class MenuBuilder: NSObject {
  private let perform: @MainActor (MenuChoice) -> Void
  /// The choices behind the last built menu's items, indexed by each item's `tag`.
  private var choices: [MenuChoice] = []

  init(perform: @escaping @MainActor (MenuChoice) -> Void) {
    self.perform = perform
    super.init()
  }

  func menu(for model: IndicatorMenu) -> NSMenu {
    let menu = NSMenu()
    choices = []
    for entry in model.items {
      switch entry {
      case .action(let title, let isChecked, let choice):
        let menuItem = NSMenuItem(title: title, action: #selector(choose(_:)), keyEquivalent: "")
        menuItem.target = self
        menuItem.state = isChecked ? .on : .off
        menuItem.tag = choices.count
        choices.append(choice)
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
    guard choices.indices.contains(sender.tag) else { return }
    perform(choices[sender.tag])
  }
}
