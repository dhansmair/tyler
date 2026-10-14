/// Why a controller decided to do nothing. A refusal has no effects.
enum Refusal: Error, Equatable {
  /// Nothing needed doing, as in "already floating".
  case message(String)
  case error(String)

  static let permissionText = """
    Accessibility permission has not been granted. Open System Settings > Privacy & Security > \
    Accessibility and enable the app that runs tylerd (for example your terminal), then try again.
    """
  static let tilingOffText = "tiling is off (use `tyler tiling on`)"
}
