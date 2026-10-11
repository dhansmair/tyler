import CoreGraphics
import TylerCore

/// A snapshot whose workspaces hold `counts` windows each (numbered from 1 across the row), all
/// with `layout`, on `current`.
func snapshot(
  counts: [Int] = [2, 1, 0, 0], current: Int = 0, layout: LayoutKind = .tall,
  tiling: ServerStatus.Tiling = .on, area: CGRect? = nil
) -> IndicatorSnapshot {
  var row = WorkspaceRow(count: counts.count)
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
