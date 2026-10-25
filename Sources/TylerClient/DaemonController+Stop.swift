import TylerProtocol

/// How `stop` and `restart` end the running tylerd.
extension DaemonController {
  /// How a stop leaves the windows and the workspaces.
  enum Ending {
    /// Windows back where they were, workspaces gone: `tyler stop`, or a tylerd too old for more.
    case puttingWindowsBack
    /// Windows where they are, workspaces handed over.
    case handingOver
    /// Windows back where they were, workspaces handed over: for a next tylerd under another
    /// grant, which may not have it yet.
    case handingOverPuttingWindowsBack
  }

  enum StopOutcome {
    case notRunning
    /// How it ended: what was asked, or less if the tylerd was too old for it.
    case stopped(Int32, Ending)
  }

  /// Ends the running tylerd as `asked` and waits for it to quit: SIGTERM runs its normal
  /// shutdown, SIGUSR1 hands over, SIGUSR2 hands over with the windows put back. A tylerd too
  /// old for a hand-over is sent SIGTERM, which it understands, rather than a signal it would die
  /// of without cleaning up.
  func stop(_ asked: Ending = .puttingWindowsBack) throws(DaemonError) -> StopOutcome {
    guard let status = try runningStatus() else { return .notRunning }
    let pid = status.pid
    let ending: Ending =
      switch asked {
      case .handingOver where status.keepsWindowsOnRestart == true: .handingOver
      case .handingOverPuttingWindowsBack where status.putsWindowsBackOnHandOver == true:
        .handingOverPuttingWindowsBack
      case .puttingWindowsBack, .handingOver, .handingOverPuttingWindowsBack: .puttingWindowsBack
      }
    let signalled =
      switch ending {
      case .puttingWindowsBack: system.terminate(pid)
      case .handingOver: system.requestHandOver(pid, puttingWindowsBack: false)
      case .handingOverPuttingWindowsBack: system.requestHandOver(pid, puttingWindowsBack: true)
      }
    guard signalled else { throw .cannotSignal(pid) }
    var waited = Duration.zero
    while system.isRunning(pid) {
      guard waited < stopTimeout else { throw .stillRunning(pid) }
      system.pause(pollInterval)
      waited += pollInterval
    }
    return .stopped(pid, ending)
  }

  /// What `restart` says about how the old tylerd ended, and why.
  static func note(_ ending: Ending, _ change: GrantChange?) -> String {
    let reason =
      switch change {
      case .movesElsewhere: "the new tylerd runs from elsewhere, with a permission of its own"
      case .newAdHocBuild:
        "the new build is signed ad hoc, which macOS treats as another app that needs the "
          + "permission again"
      case nil: "the old tylerd could not hand over"
      }
    return switch (ending, change) {
    case (.handingOver, _): ""
    case (.handingOverPuttingWindowsBack, _):
      "\n(\(reason), so the old one put its windows back where they were; they go back to "
        + "their workspaces once the new one has the permission)"
    case (.puttingWindowsBack, nil): "\n(\(reason), so its windows went back where they were)"
    case (.puttingWindowsBack, _):
      "\n(\(reason), so the old one put its windows back where they were)"
    }
  }
}
