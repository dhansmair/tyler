import CoreGraphics
import TylerCore
import TylerProtocol

/// A snapshot whose workspaces hold `counts` windows each (numbered from 1 across the row), all
/// with `layout`, on `current`. The workspaces are numbered `numbers`, or from 1.
func snapshot(
  counts: [Int] = [2, 1, 0, 0], current: Int = 0, layout: LayoutKind = .tall,
  tiling: ServerStatus.Tiling = .on, area: CGRect? = nil, numbers: [Int]? = nil
) -> IndicatorSnapshot {
  var row = numbers.map { WorkspaceRow(numbers: $0) } ?? WorkspaceRow(count: counts.count)
  var next = 1
  for (index, count) in counts.enumerated() {
    row[index].layout = layout
    for _ in 0..<count {
      row[index].append(WindowID(UInt32(next)))
      next += 1
    }
  }
  row.select(current)
  return IndicatorSnapshot(row: row, tiling: tiling, area: area)
}

extension Workspace {
  mutating func setSize(_ size: WindowSize, of windowID: WindowID) {
    update(\.strip) { strip, _ in strip.setSize(size, of: windowID) }
  }

  mutating func adjustRatio(by delta: Double) {
    update(\.tall) { tall, _ in tall.adjustRatio(by: delta) }
  }
}
