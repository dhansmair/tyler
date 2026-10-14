import CoreGraphics

package struct StripLayoutState: LayoutState {
  package private(set) var sizes: [WindowID: WindowSize]

  package init() {
    self.init(sizes: [:])
  }

  package init(sizes: [WindowID: WindowSize]) {
    self.sizes = sizes
  }

  package func size(of windowID: WindowID) -> WindowSize {
    sizes[windowID] ?? .half
  }

  package enum SizeChange: Equatable, Sendable {
    case changed
    case unchanged
    /// A `quarter` needs a neighbour to share its column with, and neither is free.
    case noPartner
  }

  /// Sets the size the way a user means it. A `quarter` takes a neighbour along to share its
  /// column: the next window, or the previous one if the next already shares a column or there is
  /// none. Leaving `quarter` puts the column mate back to `half`.
  package mutating func setSizeWithPartner(
    _ size: WindowSize, of windowID: WindowID, in windows: [WindowID]
  ) -> SizeChange {
    guard let index = windows.firstIndex(of: windowID) else { return .unchanged }
    guard self.size(of: windowID) != size else { return .unchanged }
    if size == .quarter {
      let isFree = { (index: Int) in
        windows.indices.contains(index) && self.size(of: windows[index]) != .quarter
      }
      guard let partner = [index + 1, index - 1].first(where: isFree) else { return .noPartner }
      sizes[windows[partner]] = .quarter
    } else {
      unpair(windowID, in: windows)
    }
    sizes[windowID] = size
    return .changed
  }

  @discardableResult
  package mutating func setSize(_ size: WindowSize, of windowID: WindowID) -> Bool {
    guard self.size(of: windowID) != size else { return false }
    sizes[windowID] = size
    return true
  }

  /// Puts the column mate of a leaving `quarter` back to `half`, so it doesn't stay a lone
  /// quarter.
  package mutating func remove(_ windowID: WindowID, from windows: [WindowID]) {
    unpair(windowID, in: windows)
    sizes[windowID] = nil
  }

  /// The window keeps its size, but a `quarter` arrives as `half`: its column mate stayed behind.
  package mutating func adopt(_ windowID: WindowID, from other: StripLayoutState) {
    let size = other.size(of: windowID)
    setSize(size == .quarter ? .half : size, of: windowID)
  }

  func columns(of windows: [WindowID]) -> StripColumns {
    StripColumns(sizes: windows.map(size(of:)))
  }

  private mutating func unpair(_ windowID: WindowID, in windows: [WindowID]) {
    guard size(of: windowID) == .quarter, let index = windows.firstIndex(of: windowID) else {
      return
    }
    let columns = columns(of: windows)
    guard let column = columns.column(of: index) else { return }
    for mate in columns.columns[column] where mate != index {
      sizes[windows[mate]] = nil
    }
  }
}

extension StripLayoutState: Codable {
  private struct SavedSize: Codable {
    let id: WindowID
    let size: WindowSize
  }

  private enum CodingKeys: String, CodingKey {
    case sizes
  }

  /// The sizes are a list, ordered by window, since JSON keys must be strings.
  package init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let saved = try container.decode([SavedSize].self, forKey: .sizes)
    self.init(
      sizes: Dictionary(saved.map { ($0.id, $0.size) }, uniquingKeysWith: { first, _ in first }))
  }

  package func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    let saved = sizes.sorted { $0.key < $1.key }.map { SavedSize(id: $0.key, size: $0.value) }
    try container.encode(saved, forKey: .sizes)
  }
}
