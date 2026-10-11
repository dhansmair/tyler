/// `[displays]`: which workspaces each display has, by display number.
extension Config {
  /// The numbers a workspace can have.
  static let workspaceNumberRange = 1...99
  /// The most workspaces one display may list (as many as the menu bar map shows).
  static let workspacesPerDisplayRange = 1...10

  /// The workspace numbers of displays 1 to `displayCount`, and of any other display that
  /// `[displays]` lists. A listed display gets its list. Any other display gets `workspaces.count`
  /// workspaces numbered on from the highest number so far, so without `[displays]` display 1 has
  /// 1 to count, display 2 the next count, and so on.
  public func workspaceNumbers(displayCount: Int) -> [[Int]] {
    let last = max(displayCount, displays.keys.max() ?? 0, 1)
    var highest = displays.values.joined().max() ?? 0
    return (1...last).map { display in
      if let listed = displays[display] { return listed }
      defer { highest += workspaces.count }
      return Array(highest + 1...highest + workspaces.count)
    }
  }

  static func displays(_ value: TOMLValue) throws(ConfigError) -> [Int: [Int]] {
    guard case .table(let table) = value else {
      throw .invalid("displays must be a table: write [displays] and put 1 = [1, 2, 3] below it")
    }
    var displays: [Int: [Int]] = [:]
    var listedOn: [Int: Int] = [:]
    for (key, value) in table.sorted(by: { $0.key < $1.key }) {
      guard let display = Int(key), display >= 1, String(display) == key else {
        throw .invalid("displays.\(key): name a display by its number, 1 or more")
      }
      let numbers = try workspaceList(value, name: "displays.\(key)")
      for number in numbers {
        if let other = listedOn.updateValue(display, forKey: number) {
          throw .invalid(
            "workspace \(number) is listed for display \(other) and display \(display)")
        }
      }
      displays[display] = numbers
    }
    return displays
  }

  private static func workspaceList(_ value: TOMLValue, name: String) throws(ConfigError) -> [Int] {
    let message =
      "\(name) must list workspace numbers, \(workspaceNumberRange.lowerBound) to "
      + "\(workspaceNumberRange.upperBound), like [1, 2, 3]"
    guard case .array(let values) = value else { throw .invalid(message) }
    var numbers: [Int] = []
    for value in values {
      guard case .integer(let number) = value, workspaceNumberRange.contains(number) else {
        throw .invalid(message)
      }
      guard !numbers.contains(number) else {
        throw .invalid("\(name) lists workspace \(number) twice")
      }
      numbers.append(number)
    }
    guard workspacesPerDisplayRange.contains(numbers.count) else {
      throw .invalid(
        "\(name) must list \(workspacesPerDisplayRange.lowerBound) to "
          + "\(workspacesPerDisplayRange.upperBound) workspaces")
    }
    return numbers.sorted()
  }
}
