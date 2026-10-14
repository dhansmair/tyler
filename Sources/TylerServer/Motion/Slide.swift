import TylerCore

/// A slide in progress. `finals` is where every window involved must end up, whether the slide
/// runs to the end or is cut short.
struct Slide {
  let id: Int
  let task: Task<Void, Never>
  let finals: [Placement]
}
