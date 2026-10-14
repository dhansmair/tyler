/// Commands that manage the `tylerd` process instead of asking it to do something.
package enum DaemonCommand: String, CaseIterable, Sendable {
  case start
  case stop
  case restart
  case status
}
