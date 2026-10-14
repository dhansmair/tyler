extension Config {
  /// How long windows take to move to their new places, in milliseconds; 0 moves them at once.
  package struct Animations: Equatable, Sendable {
    static let durationRange = 0...1000

    /// The windows of `tyler window swap`.
    package var swap: Int

    package init(swap: Int = 250) {
      self.swap = swap
    }
  }
}

extension Config.Animations {
  init(_ value: TOMLValue) throws(ConfigError) {
    self = try Section.read("animations", value, into: Self(), Self.settings)
  }

  /// The keys of `[animations]`, and how each is read.
  static let settings: [Setting<Self>] = [swapSetting]

  private static let swapSetting = Setting<Self>(
    "swap",
    read: { animations, value, name throws(ConfigError) in
      animations.swap = try Section.integer(value, name, in: durationRange, unit: "milliseconds")
    }, write: { .integer($0.swap) })
}
