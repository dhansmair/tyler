import Foundation
import TylerConfig

@testable import TylerServer

/// A config file whose contents the test can change between reloads. `@unchecked Sendable`
/// because `contents` is only touched under `lock`.
package final class FakeConfigFile: @unchecked Sendable {
  package enum Contents {
    case missing
    case config(Config)
    case broken(ConfigError)
  }

  package static let path = "/test/tyler.toml"

  private let lock = NSLock()
  private var contents: Contents

  package init(_ contents: Contents = .missing) {
    self.contents = contents
  }

  package func write(_ contents: Contents) {
    lock.withLock { self.contents = contents }
  }

  package var source: ConfigSource {
    ConfigSource(path: Self.path) { () throws(ConfigError) -> Config? in
      switch self.lock.withLock({ self.contents }) {
      case .missing: return nil
      case .config(let config): return config
      case .broken(let error): throw error
      }
    }
  }
}
