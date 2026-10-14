/// One key of a config section: how its value goes into the section, and how it comes back out
/// as the file would write it (`nil` when the section doesn't set it). `read` also gets the
/// setting's full name (`gaps.inner`), for its error messages.
struct Setting<Value>: Sendable {
  typealias Read = @Sendable (inout Value, TOMLValue, _ name: String) throws(ConfigError) -> Void
  typealias Write = @Sendable (Value) -> TOMLValue?

  let key: String
  let read: Read
  let write: Write

  init(_ key: String, read: @escaping Read, write: @escaping Write) {
    self.key = key
    self.read = read
    self.write = write
  }
}
