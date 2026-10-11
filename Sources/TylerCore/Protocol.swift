import Foundation

/// A command sent from the `tyler` client to the `tylerd` server.
public enum Request: Codable, Equatable, Sendable {
  case ping
  /// Asks the server about itself: pid, binary, config, tiling.
  case status
  case list
  /// Reads the config file again and applies it.
  case reload
  case retile
  case tiling(TilingMode)
  case focus(ListTarget)
  case swap(ListTarget)
  case layout(LayoutChoice)
  /// Sets the focused window's size in the strip layout.
  case size(SizeChoice)
  /// Changes the master column's share of the width by this amount.
  case ratio(Double)
  /// Floats the focused window, or tiles it again if it is floating.
  case toggleFloat
  /// Switches to another workspace.
  case workspace(WorkspaceTarget)
  /// Sends the focused window to another workspace; with `follow`, the view goes along.
  case moveToWorkspace(WorkspaceTarget, follow: Bool)
}

/// The server's reply to a `Request`.
public enum Response: Codable, Equatable, Sendable {
  case pong
  /// The command succeeded and there is nothing to report.
  case ok
  /// The command succeeded; the text is for the user.
  case message(String)
  case windows([WindowInfo])
  case status(ServerStatus)
  case error(String)
}

/// Wire format: one JSON document per line, terminated by `\n`.
public enum Wire {
  /// The byte that ends every message: `\n`.
  public static let terminator: UInt8 = 0x0A

  public static func encode<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    var data = try encoder.encode(value)
    data.append(terminator)
    return data
  }

  public static func decode<T: Decodable>(_ type: T.Type, from line: Data) throws -> T {
    try JSONDecoder().decode(type, from: line)
  }
}
