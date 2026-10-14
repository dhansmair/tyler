/// What moving the windows cost during one slide, swipe or drag, for its line in the log. Times
/// are offsets from when the interaction began.
package struct MotionCost: Equatable, Sendable {
  package struct Write: Equatable, Sendable {
    package let windowID: WindowID
    package let duration: Duration

    package init(windowID: WindowID, duration: Duration) {
      self.windowID = windowID
      self.duration = duration
    }
  }

  /// The moves written for tylerd off its main thread, a queue per app.
  package struct Queued: Equatable, Sendable {
    package private(set) var written = 0
    /// Moves a newer one replaced before they were written: frames a slow app skipped.
    package private(set) var skipped = 0
    package private(set) var time = Duration.zero
    package private(set) var slowest: Write?

    package init() {}

    package mutating func add(written: Int, skipped: Int, time: Duration, slowest: Write?) {
      self.written += written
      self.skipped += skipped
      self.time += time
      if let slowest, slowest.duration > self.slowest?.duration ?? .zero { self.slowest = slowest }
    }
  }

  package private(set) var frames = 0
  /// When the first frame began: anything done after starting a slide delays it.
  package private(set) var firstFrame: Duration?
  package private(set) var longestFrameGap = Duration.zero
  package private(set) var writes = 0
  package private(set) var writeTime = Duration.zero
  package private(set) var slowestWrite: Write?
  /// Window updates from macOS meanwhile: mostly the echoes of the writes.
  package private(set) var updates = 0
  package private(set) var queued = Queued()
  private var lastFrame: Duration?

  package init() {}

  package mutating func frameStarted(at time: Duration) {
    frames += 1
    if firstFrame == nil { firstFrame = time }
    if let lastFrame { longestFrameGap = max(longestFrameGap, time - lastFrame) }
    lastFrame = time
  }

  package mutating func wrote(_ windowID: WindowID, taking duration: Duration) {
    writes += 1
    writeTime += duration
    if duration > slowestWrite?.duration ?? .zero {
      slowestWrite = Write(windowID: windowID, duration: duration)
    }
  }

  package mutating func windowUpdated() {
    updates += 1
  }

  package mutating func add(_ queued: Queued) {
    self.queued.add(
      written: queued.written, skipped: queued.skipped, time: queued.time, slowest: queued.slowest)
  }

  /// `24 frames (first after 9.0 ms, longest gap 21.0 ms), 96 writes in 142.0 ms, slowest 9.0 ms
  /// #812 (Firefox), 98 updates`
  package func summary(naming name: (WindowID) -> String) -> String {
    var parts: [String] = []
    if frames > 0 {
      let first = Self.milliseconds(firstFrame ?? .zero)
      parts.append(
        "\(frames) frames (first after \(first), longest gap \(Self.milliseconds(longestFrameGap)))"
      )
    }
    parts.append("\(writes) writes in \(Self.milliseconds(writeTime))")
    if let slowestWrite {
      parts.append(
        "slowest \(Self.milliseconds(slowestWrite.duration)) \(name(slowestWrite.windowID))")
    }
    if queued.written + queued.skipped > 0 {
      var text = "queued \(queued.written) in \(Self.milliseconds(queued.time))"
      text += ", \(queued.skipped) skipped"
      if let slowest = queued.slowest {
        text += ", slowest \(Self.milliseconds(slowest.duration)) \(name(slowest.windowID))"
      }
      parts.append(text)
    }
    parts.append("\(updates) updates")
    return parts.joined(separator: ", ")
  }

  private static func milliseconds(_ duration: Duration) -> String {
    let (seconds, attoseconds) = duration.components
    let tenths = (Double(seconds) * 10_000 + Double(attoseconds) / 1e14).rounded()
    return "\(tenths / 10) ms"
  }
}
