/// Lets the manager's event pumps, and any animation or throttle task, run. Main-actor isolated
/// so the yields happen where those tasks run.
@MainActor
package func settle() async {
  for _ in 0..<30 { await Task.yield() }
}
