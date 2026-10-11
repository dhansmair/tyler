/// Where a workspace belongs when its display is connected.
public enum WorkspaceHome: Codable, Equatable, Sendable {
  /// The display the config gives it, by number (1 is the primary).
  case configured(Int)
  /// The display it was last moved to with `move-workspace-to-display`.
  case pinned(DisplayKey)
}

/// The workspaces of every connected display: one row per display, in display-number order.
/// Workspace numbers are global, so each number is on exactly one display.
///
/// A workspace lives on its home display, or on display 1 while that one isn't connected. When
/// displays come and go, `reassign` moves the workspaces accordingly.
public struct DisplayRows: Equatable, Sendable {
  /// A connected display and its row.
  public struct Entry: Equatable, Sendable {
    public let key: DisplayKey
    public var row: WorkspaceRow

    public init(key: DisplayKey, row: WorkspaceRow) {
      self.key = key
      self.row = row
    }
  }

  /// Names the only row while no display is known.
  public static let unknownDisplay = DisplayKey("")

  /// The connected displays, in display-number order; never empty.
  public private(set) var entries: [Entry]
  /// Each workspace's home, by number.
  public private(set) var homes: [Int: WorkspaceHome]
  /// The workspace each disconnected display had on screen, so it comes back with it.
  public private(set) var rememberedCurrent: [DisplayKey: Int] = [:]
  /// The display commands act on.
  public private(set) var focusedKey: DisplayKey

  /// Rows for the displays `keys` (in display-number order; one unknown display if empty), where
  /// `configured[n]` lists the workspaces of display n + 1. Workspaces of displays that aren't
  /// connected start on display 1. Display 1 has focus.
  public init(keys: [DisplayKey], configured: [[Int]]) {
    let keys = keys.isEmpty ? [Self.unknownDisplay] : keys
    var homes: [Int: WorkspaceHome] = [:]
    for (index, numbers) in configured.enumerated() {
      for number in numbers where homes[number] == nil {
        homes[number] = .configured(index + 1)
      }
    }
    var placed = Dictionary(grouping: homes.keys) {
      Self.position(forHome: homes[$0], among: keys)
    }
    var next = (homes.keys.max() ?? 0) + 1
    for position in keys.indices where placed[position] == nil {
      homes[next] = .pinned(keys[position])
      placed[position] = [next]
      next += 1
    }
    self.homes = homes
    entries = keys.indices.map {
      Entry(key: keys[$0], row: WorkspaceRow(numbers: placed[$0] ?? []))
    }
    focusedKey = keys[0]
  }

  /// Rows as a previous tylerd left them: `entries` (one unknown display if empty), each
  /// workspace's home, and the display with focus (display 1 if it isn't among `entries`).
  public init(entries: [Entry], homes: [Int: WorkspaceHome], focusedKey: DisplayKey?) {
    self.entries =
      entries.isEmpty
      ? [Entry(key: Self.unknownDisplay, row: WorkspaceRow(numbers: []))] : entries
    self.homes = homes
    let keys = self.entries.map(\.key)
    self.focusedKey = focusedKey.flatMap { keys.contains($0) ? $0 : nil } ?? keys[0]
  }

  // MARK: - Lookups

  public var keys: [DisplayKey] { entries.map(\.key) }

  /// The position in `entries` of the display `key`, if connected.
  public func position(of key: DisplayKey) -> Int? {
    entries.firstIndex { $0.key == key }
  }

  /// The row of the focused display.
  public var focused: WorkspaceRow {
    get { entries[focusedPosition].row }
    _modify { yield &entries[focusedPosition].row }
  }

  private var focusedPosition: Int { position(of: focusedKey) ?? 0 }

  /// The row of the display at `position` in `entries`.
  public subscript(position: Int) -> WorkspaceRow {
    get { entries[position].row }
    _modify { yield &entries[position].row }
  }

  /// Where the workspace numbered `number` is: its display's position and its index in that row.
  public func location(ofNumber number: Int) -> (position: Int, index: Int)? {
    for (position, entry) in entries.enumerated() {
      if let index = entry.row.index(ofNumber: number) { return (position, index) }
    }
    return nil
  }

  /// Where the window is: its display's position and its workspace's index in that row.
  public func location(of windowID: WindowID) -> (position: Int, index: Int)? {
    for (position, entry) in entries.enumerated() {
      if let index = entry.row.index(containing: windowID) { return (position, index) }
    }
    return nil
  }

  /// Every window on any workspace of any display.
  public var allWindows: Set<WindowID> {
    entries.reduce(into: []) { $0.formUnion($1.row.allWindows) }
  }

  // MARK: - Changes

  /// Makes the display `key` the one commands act on. Returns false if it isn't connected.
  @discardableResult
  public mutating func focus(_ key: DisplayKey) -> Bool {
    guard position(of: key) != nil else { return false }
    focusedKey = key
    return true
  }

  /// Takes the connected displays `keys` (in display-number order) and moves every workspace to
  /// the display it now belongs on. A workspace that was on screen stays on screen when it moves;
  /// a display that comes back shows what it showed before it left. With no displays nothing
  /// changes. Returns whether anything did.
  ///
  /// `configured` (where `configured[n]` lists display n + 1's workspaces) adds the workspaces
  /// that don't exist yet, such as those the config gives a display that just connected. It
  /// never removes any: a workspace whose display goes away waits on display 1.
  @discardableResult
  public mutating func reassign(to keys: [DisplayKey], configured: [[Int]] = []) -> Bool {
    guard !keys.isEmpty else { return false }
    let added = addMissing(configured)
    guard added || keys != self.keys else { return false }
    rebuild(on: keys)
    return true
  }

  /// Adds an empty workspace, at home on its configured display, for each number in
  /// `configured` that no workspace has. Returns whether it added any.
  private mutating func addMissing(_ configured: [[Int]]) -> Bool {
    var added = false
    for (index, numbers) in configured.enumerated() {
      for number in numbers where location(ofNumber: number) == nil {
        homes[number] = homes[number] ?? .configured(index + 1)
        entries[0].row.insert(Workspace(), number: number)
        added = true
      }
    }
    return added
  }

  /// Takes new workspace numbers from the config, where `configured[n]` lists display n + 1's.
  /// Workspaces whose number the config no longer has go, their windows joining the last
  /// workspace of their row; new numbers start empty. Each workspace then moves to its home: the
  /// display the config gives it, unless it was moved by hand and keeps its number.
  public mutating func setConfigured(_ configured: [[Int]]) {
    var newHomes: [Int: WorkspaceHome] = [:]
    for (index, numbers) in configured.enumerated() {
      for number in numbers where newHomes[number] == nil {
        newHomes[number] = .configured(index + 1)
      }
    }
    for (number, home) in homes where newHomes[number] != nil {
      if case .pinned = home { newHomes[number] = home }
    }
    let existing = Set(entries.flatMap(\.row.numbers))
    var next = (Array(newHomes.keys) + existing).max().map { $0 + 1 } ?? 1
    for position in entries.indices {
      var kept = entries[position].row.numbers.filter { newHomes[$0] != nil }
      if position == 0 { kept += newHomes.keys.filter { !existing.contains($0) } }
      if kept.isEmpty {
        newHomes[next] = .pinned(entries[position].key)
        kept = [next]
        next += 1
      }
      entries[position].row.setNumbers(kept)
    }
    homes = newHomes
    rebuild(on: keys)
  }

  /// Moves every workspace to the display among `keys` it belongs on (see `reassign`).
  private mutating func rebuild(on keys: [DisplayKey]) {
    let before = Dictionary(
      uniqueKeysWithValues: entries.map { ($0.key, $0.row.number(at: $0.row.currentIndex)) })
    for (key, number) in before where !keys.contains(key) && key != Self.unknownDisplay {
      rememberedCurrent[key] = number
    }
    var placed: [Int: [(number: Int, workspace: Workspace)]] = [:]
    for entry in entries {
      for index in entry.row.indices {
        let number = entry.row.number(at: index)
        placed[Self.position(forHome: homes[number], among: keys), default: []].append(
          (number, entry.row[index]))
      }
    }
    var next = (Array(homes.keys) + before.values).max().map { $0 + 1 } ?? 1
    entries = keys.indices.map { position in
      var workspaces = placed[position] ?? []
      if workspaces.isEmpty {
        homes[next] = .pinned(keys[position])
        workspaces = [(next, Workspace())]
        next += 1
      }
      var row = WorkspaceRow(numbers: workspaces.map(\.number))
      for (number, workspace) in workspaces {
        if let index = row.index(ofNumber: number) { row[index] = workspace }
      }
      return Entry(key: keys[position], row: row)
    }
    let onScreen = Set(before.values)
    for position in entries.indices {
      selectCurrent(at: position, before: before[entries[position].key], onScreen: onScreen)
    }
    if position(of: focusedKey) == nil { focusedKey = keys[0] }
  }

  /// Why `moveWorkspace` refused.
  public enum MoveError: Error, Equatable {
    case noSuchWorkspace
    case noSuchDisplay
    case alreadyThere
    /// The workspace is its display's only one.
    case lastWorkspace
  }

  /// Moves the workspace numbered `number` to the display `key`, where it goes in by number,
  /// becomes current and gets focus; it now belongs there. If it was current on its old display,
  /// that one shows the next workspace (or the previous one at the end of the row).
  public mutating func moveWorkspace(number: Int, to key: DisplayKey) throws(MoveError) {
    guard let source = location(ofNumber: number) else { throw .noSuchWorkspace }
    guard let target = position(of: key) else { throw .noSuchDisplay }
    guard source.position != target else { throw .alreadyThere }
    guard let workspace = entries[source.position].row.remove(number: number) else {
      throw .lastWorkspace
    }
    entries[target].row.insert(workspace, number: number)
    entries[target].row.select(entries[target].row.index(ofNumber: number) ?? 0)
    homes[number] = .pinned(key)
    focusedKey = key
  }

  // MARK: - Helpers

  /// The position (among `keys`) of the display a workspace with this home belongs on.
  private static func position(forHome home: WorkspaceHome?, among keys: [DisplayKey]) -> Int {
    switch home {
    case .configured(let display)?: display <= keys.count ? display - 1 : 0
    case .pinned(let key)?: keys.firstIndex(of: key) ?? 0
    case nil: 0
    }
  }

  /// After a reassignment, picks the current workspace of the display at `position`, in this
  /// order: the one it had (`before`, if it had one and kept it); one that was on screen on
  /// another display; the one it showed before it was disconnected; the next after the one it
  /// had, or its last; its first.
  private mutating func selectCurrent(at position: Int, before: Int?, onScreen: Set<Int>) {
    let row = entries[position].row
    let key = entries[position].key
    let remembered = rememberedCurrent.removeValue(forKey: key)
    let index =
      before.flatMap(row.index(ofNumber:))
      ?? row.indices.first { onScreen.contains(row.number(at: $0)) }
      ?? remembered.flatMap(row.index(ofNumber:))
      ?? before.map { old in row.numbers.firstIndex { $0 > old } ?? row.count - 1 } ?? 0
    entries[position].row.select(index)
  }
}
