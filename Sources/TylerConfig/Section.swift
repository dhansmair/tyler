/// Reading a `[section]` table and its values. The error messages name the section's keys from
/// its settings, so they can't drift from what is accepted.
enum Section {
  static func read<Value>(
    _ name: String, _ value: TOMLValue, into defaults: Value, _ settings: [Setting<Value>]
  ) throws(ConfigError) -> Value {
    let keys = settings.map(\.key)
    guard case .table(let table) = value else {
      throw .invalid(
        "\(name) must be a table: write [\(name)] and put \(list(keys, "and")) below it")
    }
    var section = defaults
    for (key, value) in table.sorted(by: { $0.key < $1.key }) {
      guard let setting = settings.first(where: { $0.key == key }) else {
        throw .invalid("unknown setting '\(name).\(key)' (use \(list(keys, "or")))")
      }
      try setting.read(&section, value, "\(name).\(key)")
    }
    return section
  }

  /// A section as a table, with each setting it sets.
  static func document<Value>(_ section: Value, _ settings: [Setting<Value>]) -> TOMLValue {
    .table(
      Dictionary(
        uniqueKeysWithValues: settings.compactMap { setting in
          setting.write(section).map { (setting.key, $0) }
        }))
  }

  static func boolean(_ value: TOMLValue, _ name: String) throws(ConfigError) -> Bool {
    guard case .boolean(let isOn) = value else { throw .invalid("\(name) must be true or false") }
    return isOn
  }

  static func points(_ value: TOMLValue, _ name: String) throws(ConfigError) -> Int {
    guard case .integer(let points) = value, points >= 0 else {
      throw .invalid("\(name) must be a whole number of points, 0 or more")
    }
    return points
  }

  /// A whole number in `range`. A range of two values reads "3 or 4"; others name the unit.
  static func integer(
    _ value: TOMLValue, _ name: String, in range: ClosedRange<Int>, unit: String? = nil
  ) throws(ConfigError) -> Int {
    guard case .integer(let number) = value, range.contains(number) else {
      if range.count == 2 {
        throw .invalid("\(name) must be \(range.lowerBound) or \(range.upperBound)")
      }
      let kind = unit.map { "a whole number of \($0)" } ?? "a whole number"
      throw .invalid("\(name) must be \(kind), \(range.lowerBound) to \(range.upperBound)")
    }
    return number
  }

  /// A number in `range`; whole numbers count too.
  static func number(
    _ value: TOMLValue, _ name: String, in range: ClosedRange<Double>, unit: String
  ) throws(ConfigError) -> Double {
    let number: Double? =
      switch value {
      case .float(let number): number
      case .integer(let number): Double(number)
      default: nil
      }
    guard let number, range.contains(number) else {
      throw .invalid(
        "\(name) must be a number of \(unit), \(range.lowerBound) to \(range.upperBound)")
    }
    return number
  }

  /// "a", "a and b", "a, b and c".
  private static func list(_ items: [String], _ conjunction: String) -> String {
    guard let last = items.last, items.count > 1 else { return items.first ?? "" }
    return items.dropLast().joined(separator: ", ") + " \(conjunction) " + last
  }
}
