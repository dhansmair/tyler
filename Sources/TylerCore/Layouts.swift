import CoreGraphics

/// xmonad's "Tall": the first window (the master) fills the left column and the rest are
/// stacked, with equal heights, in the right column. Two windows sit side by side, three give
/// one on the left and two above each other on the right.
public struct TallLayout: Layout {
  public init() {}

  public func frames(count: Int, in area: CGRect, parameters: LayoutParameters) -> [CGRect] {
    guard count > 0 else { return [] }
    let box = IntegerBox(area, inset: parameters.outerGap)
    guard count > 1 else { return [box.rect] }

    let gap = Int(parameters.innerGap.rounded())
    let columns = IntegerBox.split(origin: box.minX, length: box.width, count: 2, gap: gap)
    // `split` shares space evenly; the ratio replaces that with a master/stack division.
    let available = max(0, box.width - gap)
    let mainWidth = Int((Double(available) * parameters.mainRatio).rounded())
    let stackWidth = available - mainWidth
    let mainX = columns[0].origin
    let stackX = mainX + mainWidth + gap

    let main = IntegerBox(
      minX: mainX, minY: box.minY, width: mainWidth, height: box.height)
    let rows = IntegerBox.split(
      origin: box.minY, length: box.height, count: count - 1, gap: gap)
    let stack = rows.map { row in
      IntegerBox(minX: stackX, minY: row.origin, width: stackWidth, height: row.length)
    }
    return ([main] + stack).map(\.rect)
  }
}

/// Every window gets the whole area. The focused window is the one you see, because focusing
/// raises it.
public struct FullLayout: Layout {
  public init() {}

  public func frames(count: Int, in area: CGRect, parameters: LayoutParameters) -> [CGRect] {
    guard count > 0 else { return [] }
    let box = IntegerBox(area, inset: parameters.outerGap)
    return Array(repeating: box.rect, count: count)
  }
}
