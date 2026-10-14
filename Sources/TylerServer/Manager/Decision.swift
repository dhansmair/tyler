/// What a controller decided to do, with the summary for the command's reply, which also says
/// what went wrong while the effects ran.
struct Decision {
  var summary: String?
  var effects: [Effect]

  init(_ summary: String? = nil, effects: [Effect] = []) {
    self.summary = summary
    self.effects = effects
  }
}
