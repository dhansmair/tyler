import CoreGraphics
import TylerCore

extension Layout {
  /// The frames for windows 1 to `count`, as most tests ask for them.
  package func frames(
    count: Int, in area: CGRect, state: State = State(), gaps: LayoutGaps = LayoutGaps()
  ) -> [CGRect] {
    frames(
      of: (0..<count).map { WindowID(UInt32($0 + 1)) }, state: state, in: area, gaps: gaps)
  }
}
