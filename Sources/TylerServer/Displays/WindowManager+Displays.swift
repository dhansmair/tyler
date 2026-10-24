import CoreGraphics
import TylerConfig
import TylerCore

/// The displays and their rows of workspaces.
extension WindowManager {
  /// The focused display's row, which commands act on.
  var workspaces: WorkspaceRow {
    get { rows.focused }
    _modify { yield &rows.focused }
  }

  /// The display commands act on: the one of the focused window, or the one a command last
  /// went to; `nil` while it isn't connected.
  var focusedDisplay: DisplayInfo? { display(for: rows.focusedKey) }

  /// The connected displays in the order tyler numbers them, each with its neighbours and
  /// parking edge (see `DisplayArrangement`).
  var connectedDisplays: [DisplayInfo] {
    DisplayArrangement.sided(DisplayArrangement.ordered(displays.displays))
  }

  /// The workspace numbers the config gives each of `displayCount` displays (at least one).
  static func configuredNumbers(_ config: Config, displayCount: Int) -> [[Int]] {
    config.workspaceNumbers(displayCount: max(1, displayCount))
  }

  /// The workspace numbers the config gives each connected display.
  func configuredNumbers(_ config: Config) -> [[Int]] {
    Self.configuredNumbers(config, displayCount: displays.displays.count)
  }

  /// Fresh rows for the connected displays, as the config numbers them.
  func freshRows() -> DisplayRows {
    DisplayRows(
      keys: connectedDisplays.map(\.key), configured: configuredNumbers(config),
      newLayout: config.layouts.initial)
  }

  /// The connected display named `key`, if any.
  func display(for key: DisplayKey) -> DisplayInfo? {
    connectedDisplays.first { $0.key == key }
  }

  /// The display of the row at `position` in `rows`, if connected.
  func display(at position: Int) -> DisplayInfo? {
    display(for: rows.entries[position].key)
  }

  // MARK: - Reconfiguration

  /// How long tylerd waits after the last display change before it acts. macOS sends each
  /// change as a burst over about 0.3 s, and one second after the last one `NSScreen` is up to
  /// date and macOS has finished moving windows (measured; see `devdocs/macos-behaviour.md`).
  static let displaySettleDelay = Duration.seconds(1)

  /// Starts following display changes.
  func startDisplays() {
    let changes = displays.changes
    displayPump = Task { [weak self] in
      for await _ in changes {
        self?.displaysChanged()
      }
    }
  }

  /// Stops following display changes, dropping one still pending.
  func stopDisplays() {
    displayPump?.cancel()
    displayPump = nil
    displaySettling.cancel()
  }

  /// Notes a display change and (re)starts the wait for the displays to settle, so a burst of
  /// changes is acted on once, after the last one.
  func displaysChanged() {
    displaySettling.restart(after: Self.displaySettleDelay) { [weak self] in
      self?.displaysSettled()
    }
  }

  /// How often tylerd looks again whether the screen is unlocked, once the displays have settled
  /// at the lock screen.
  static let unlockCheckInterval = Duration.seconds(1)

  /// At a wake the displays settle at the lock screen, where macOS shows no windows, so placing
  /// them waits for the unlock.
  func displaysSettled() {
    guard !isScreenLocked else {
      Self.log.debug("displays settling postponed - the screen is locked")
      displaySettling.restart(after: Self.unlockCheckInterval) { [weak self] in
        self?.displaysSettled()
      }
      return
    }
    run(DisplayController(context: context).displaysSettled(model: &model))
  }
}
