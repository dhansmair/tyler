import CoreGraphics
import TylerCore

extension Config {
  /// Which layouts `layout next` goes through, and the layout new workspaces start with.
  package struct Layouts: Equatable, Sendable {
    /// The layouts `layout next` goes through, in order: never empty, without repeats. Any
    /// layout can still be chosen by name.
    package var cycle: [LayoutKind]
    /// The layout a new workspace starts with (`default` in the file).
    package var initial: LayoutKind

    package init(cycle: [LayoutKind] = LayoutKind.defaultCycle, initial: LayoutKind = .tall) {
      self.cycle = cycle.isEmpty ? LayoutKind.defaultCycle : cycle
      self.initial = initial
    }
  }
}

extension Config.Layouts {
  init(_ value: TOMLValue) throws(ConfigError) {
    self = try Section.read("layouts", value, into: Self(), Self.settings)
  }

  /// The keys of `[layouts]`, and how each is read.
  static let settings: [Setting<Self>] = [
    Setting(
      "cycle",
      read: { layouts, value, name throws(ConfigError) in
        layouts.cycle = try Self.cycle(value, name)
      }, write: { .array($0.cycle.map { .string($0.rawValue) }) }),
    Setting(
      "default",
      read: { layouts, value, name throws(ConfigError) in
        layouts.initial = try Self.layout(value, name)
      }, write: { .string($0.initial.rawValue) }),
  ]
}

extension Config.Layouts {
  private static var names: String {
    LayoutKind.allCases.map { "\"\($0.rawValue)\"" }.joined(separator: ", ")
  }

  static func layout(_ value: TOMLValue, _ name: String) throws(ConfigError) -> LayoutKind {
    guard case .string(let text) = value, let kind = LayoutKind(rawValue: text) else {
      throw .invalid("\(name) must be one of \(names)")
    }
    return kind
  }

  static func cycle(_ value: TOMLValue, _ name: String) throws(ConfigError) -> [LayoutKind] {
    let message = "\(name) must list layouts from \(names), like [\"tall\", \"full\"]"
    guard case .array(let values) = value, !values.isEmpty else { throw .invalid(message) }
    var cycle: [LayoutKind] = []
    for value in values {
      guard case .string(let text) = value, let kind = LayoutKind(rawValue: text) else {
        throw .invalid(message)
      }
      guard !cycle.contains(kind) else { throw .invalid("\(name) lists \(text) twice") }
      cycle.append(kind)
    }
    return cycle
  }
}

extension LayoutGaps {
  package init(_ gaps: Config.Gaps) {
    self.init(inner: CGFloat(gaps.inner), outer: CGFloat(gaps.outer))
  }
}
