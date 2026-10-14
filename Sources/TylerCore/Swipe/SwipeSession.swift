import CoreGraphics

/// A trackpad swipe in progress, from the fingers' travel to what the windows do: they follow the
/// fingers, and on release they settle on a neighbouring workspace or view, or back where they
/// began (see `Snap`). It decides; the caller moves the windows.
package struct SwipeSession: Sendable {
  /// The release speed, in display widths per second, from which a swipe goes on to the
  /// workspace or view it was heading for even if it is less than halfway there.
  package static let flickVelocity = 1.0
  /// The least share of a whole slide's duration that going back takes: even from close to the
  /// start, the windows settle visibly rather than snap.
  package static let returnShare = 0.6

  package let target: SwipeTarget
  /// How far the content has moved, in display widths: -1 has the next workspace fully in view,
  /// 1 the previous one. Fingers moving left move the content left, towards the next workspace
  /// (or a scrolling layout's later views, where it isn't limited to one width).
  package private(set) var offset: Double = 0
  /// The side whose incoming windows are out of their parked spots.
  private var shownSide: ScrollDirection?
  /// The pair of views whose windows are out of their parked spots, and their scroll.
  private var shownSegment: (index: Int, plan: ScrollPlan)?

  package init(target: SwipeTarget) {
    self.target = target
  }

  /// The windows the swipe may move.
  package var windows: Set<WindowID> {
    switch target {
    case .workspaceRow(let prev, let next): prev.windows.union(next.windows)
    case .view(let scroll): Set(scroll.views[0].arrangement.map(\.id))
    }
  }

  /// Takes the fingers' travel, in trackpad widths; `distance` of travel moves a whole display
  /// width.
  package mutating func move(travel: Double, distance: Double) {
    let offset = travel / distance
    switch target {
    case .workspaceRow: self.offset = min(1, max(-1, offset))
    case .view: self.offset = offset
    }
  }

  /// Where the windows go for the current offset.
  package mutating func step() -> SwipeStep {
    switch target {
    case .workspaceRow(let prev, let next):
      let side = ScrollDirection(revealedBy: offset)
      var step = SwipeStep(placements: show(side, prev: prev, next: next))
      if let side {
        step.nudges = (side == .next ? next : prev).tracks.map {
          Nudge(id: $0.id, origin: $0.position(at: abs(offset), easing: Easing.linear))
        }
      }
      return step
    case .view(let scroll):
      return viewStep(scroll)
    }
  }

  /// Where the swipe settles when the fingers lift at `velocity` (trackpad widths per second);
  /// `nil` if nothing moved and nothing will.
  package mutating func end(velocity: Double, distance: Double) -> SwipeEnding? {
    switch target {
    case .workspaceRow(let prev, let next):
      return endRow(velocity: velocity / distance, prev: prev, next: next)
    case .view(let scroll):
      return endView(scroll, velocity: velocity / distance)
    }
  }

  /// Where the windows go when the swipe is cut short: back where they were when it began.
  package func abandon() -> [Placement] {
    switch target {
    case .workspaceRow(let prev, let next):
      shownSide.map { ($0 == .next ? next : prev).returns } ?? []
    case .view(let scroll):
      shownSegment.map { scroll.resting($0.plan.windows, at: scroll.startIndex) } ?? []
    }
  }

  /// Gets the incoming windows of `side` ready to slide in, after putting back those of the side
  /// shown so far, if that was another.
  private mutating func show(
    _ side: ScrollDirection?, prev: SlidePlan, next: SlidePlan
  ) -> [Placement] {
    guard side != shownSide else { return [] }
    var placements = shownSide.map { ($0 == .next ? next : prev).returns } ?? []
    if let side { placements += (side == .next ? next : prev).start }
    shownSide = side
    return placements
  }

  private mutating func endRow(velocity: Double, prev: SlidePlan, next: SlidePlan) -> SwipeEnding {
    let point = Snap.target(
      offset: offset, velocity: velocity, points: [-1, 0, 1], flickVelocity: Self.flickVelocity)
    // A flick may head for a side whose windows haven't come out yet.
    let side = ScrollDirection(revealedBy: point) ?? shownSide
    var ending = SwipeEnding(placements: show(side, prev: prev, next: next))
    guard let side else { return ending }
    let plan = side == .next ? next : prev
    let progress = ScrollDirection(revealedBy: offset) == side ? abs(offset) : 0
    if point == 0 {
      ending.settle = .init(
        tracks: plan.tracks, finals: plan.returns, start: progress, end: 0, isReturn: true)
    } else {
      ending.settle = .init(
        tracks: plan.tracks, finals: plan.finals, start: progress, end: 1, isReturn: false)
      ending.destination = .workspace(index: plan.target)
    }
    return ending
  }

  /// The scroll between the two views the position lies between, run part-way.
  private mutating func viewStep(_ scroll: ViewScroll) -> SwipeStep {
    let position = scroll.position(movedBy: offset)
    // Still on the view the swipe began at (as at the layout's ends): nothing to bring out yet.
    if shownSegment == nil, position == scroll.offsets[scroll.startIndex] { return SwipeStep() }
    let (index, progress) = scroll.segment(at: position)
    guard let shown = shownSegment, shown.index == index else {
      return SwipeStep(placements: showSegment(index, of: scroll, at: progress).placements)
    }
    return SwipeStep(
      nudges: shown.plan.tracks.map {
        Nudge(id: $0.id, origin: $0.position(at: progress, easing: Easing.linear))
      })
  }

  /// Brings out the windows of the scroll between views `index` and `index + 1`, `progress` of
  /// the way along, after parking those of the scroll shown so far that take no part.
  private mutating func showSegment(
    _ index: Int, of scroll: ViewScroll, at progress: Double
  ) -> (placements: [Placement], plan: ScrollPlan) {
    let plan = scroll.plan(forSegment: index)
    // Out of view at both ends of the new pair, so parked at either.
    let parked =
      shownSegment.map { scroll.resting($0.plan.windows.subtracting(plan.windows), at: index) }
      ?? []
    shownSegment = (index, plan)
    return (parked + plan.placements(at: progress), plan)
  }

  /// The layout settles on the view `Snap` picks, sliding on from where it is.
  private mutating func endView(_ scroll: ViewScroll, velocity: Double) -> SwipeEnding? {
    let width = Double(scroll.viewWidth)
    let position = scroll.position(movedBy: offset)
    let target = Snap.target(
      offset: position, velocity: CGFloat(-velocity * width), points: scroll.offsets,
      flickVelocity: CGFloat(Self.flickVelocity * width))
    guard let targetIndex = scroll.offsets.firstIndex(of: target),
      shownSegment != nil || targetIndex != scroll.startIndex
    else { return nil }
    var (index, progress) = scroll.segment(at: position)
    // Resting exactly on a view, a flick may head away from the pair the position counts for.
    if targetIndex < index {
      (index, progress) = (targetIndex, 1)
    } else if targetIndex > index + 1 {
      (index, progress) = (targetIndex - 1, 0)
    }
    var ending = SwipeEnding()
    let plan: ScrollPlan
    if let shown = shownSegment, shown.index == index {
      plan = shown.plan
    } else {
      (ending.placements, plan) = showSegment(index, of: scroll, at: progress)
    }
    let isForward = targetIndex == index + 1
    ending.settle = .init(
      tracks: plan.tracks, finals: isForward ? plan.finals : plan.returns, start: progress,
      end: isForward ? 1 : 0, isReturn: targetIndex == scroll.startIndex)
    ending.destination = .view(firstVisible: scroll.views[targetIndex].firstVisible)
    return ending
  }
}
