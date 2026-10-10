# Mouse resizing: the layout follows a dragged edge

## Context
Today tylerd ignores moves and resizes on purpose (`WindowManager` header comment): a drag
never re-tiles. The user wants the layout to follow when they resize a tiled window with the
mouse, in `tall`:
- the vertical divider between the master and the stack (changes `mainRatio`), and
- the horizontal dividers between windows in the stack (needs per-row heights, which don't
  exist yet: `TallLayout` splits the stack evenly).

Decisions taken with the user (2026-10-10):
- **Live**: neighbours follow during the drag, not only on release.
- **Stack heights are kept per slot** (xmonad ResizableTall style); a new slot gets weight 1.
- **A plain move** (title-bar drag, size unchanged) **snaps back** to its slot on release.
- Everything else on release also snaps: edges that can't move (outer edges, master's top/bottom,
  `full` layout, a single window) go back to the slot.

## Long-term direction (shapes this design; goes into the roadmap)
The user's vision, to be added to `devdocs/ROADMAP.md` with a short description each:
1. **Swap by drag and drop**: drag a tiled window by its title bar onto another one, and the two
   swap slots (replaces today's snap-back).
2. **Grid layout**: same as `tall` for up to 3 windows; 4 = one per corner; 5 = right half
   split in three; 6 = both halves in three (2 columns × 3 rows). Beyond that, more columns
   appear (e.g. 3 × 3 at 9; the exact rule is still to be decided). Mouse resizing and swap
   by drag work here too.
3. **Strip layout** (niri-like): a workspace is one long horizontal strip that scrolls left and
   right; each window has its own size (full width/height, half width, half width + half
   height, …).
4. **Trackpad swipes**: e.g. three-finger swipe left/right for the previous/next workspace
   (joins M7's trackpad scroll).

What this changes in the design now (only cheap seams, nothing built for 2–4 yet):
- **Columns of rows as the shared model.** `tall` and `grid` are both "columns, each a stack of
  rows": tall = `[1, n-1]`, grid = `[⌊n/2⌋, ⌈n/2⌉]` up to 6 windows (equal to tall for
  n ≤ 3), and three or more columns beyond. So `ColumnLayout` handles any number of
  columns from the start (n-1 column dividers), even though tall only ever uses two. So the
  frames *and* the mouse-resize logic are written once, against columns and rows, and `tall`
  becomes the first user. Grid is then a new `LayoutKind` that only says how many rows go in
  each column. Mouse resizing then means: a vertical edge moves a column divider, a horizontal
  edge moves a row divider inside its column.
- **Per-row weights are kept per column** (`rowWeights: [[Double]]`), not as a tall-only
  `stackWeights`, so grid's left column can be resized too.
- **The release carries the pointer location** (`mouseReleased(at:)`), so swap-by-drag later is
  a hit test on the current placements (generic, no per-layout code) instead of a new event.
- **Pointer input is its own source**, not part of `WindowBackend`: a small `PointerInput`
  protocol (test seam) whose stream later also carries scroll and swipe events for M7.
- **Not designed for yet: strip.** It needs per-window sizes and a scroll offset (frames
  outside the visible area, interplay with parking). The `Layout` protocol will need rework
  then (it only gets a window count today); recorded as an open item rather than guessed at
  now. The resize hook below takes the window's index and new frame, which a strip layout
  could also use.

## Design

### TylerCore (pure, unit tested)
- `LayoutParameters` (`Sources/TylerCore/Layout.swift`) gains `rowWeights: [[Double]]`
  (default `[]`; `rowWeights[c][r]` is the weight of row *r* in column *c*; missing entries
  count as 1.0). `withGaps` keeps it. `mainRatio` stays the width of the first column
  (the `ratio` command and `SavedState` are unchanged in meaning). `ColumnLayout` takes column
  widths as weights; tall passes `[mainRatio, 1 - mainRatio]`. When grid gets a third column,
  a `columnWeights` parameter joins (not added now: nothing would use it yet).
- New `ColumnLayout` helper (in `Layouts.swift` or its own file): given column sizes, area and
  parameters, produces frames (columns split by `mainRatio`, rows by weight) and infers new
  parameters from a resized frame. Weighted split goes next to `IntegerBox.split` (whole points,
  remainder to the earliest rows) so equal weights give exactly today's frames (existing
  `LayoutTests` pass unchanged).
- `TallLayout` becomes columns `[1, n-1]` through `ColumnLayout`.
- `Layout` protocol gets a second requirement with a default:
  `func parameters(afterResizing index: Int, to frame: CGRect, count: Int, in area: CGRect,
  parameters: LayoutParameters) -> LayoutParameters?` — default `nil` (doesn't follow the
  mouse, e.g. `FullLayout`). Column layouts implement it via `ColumnLayout`:
  - a window's left or right edge moved, where that edge is a divider between two columns →
    the new column widths (for tall: `mainRatio` from that edge);
  - top edge moved (not the first row) → divider between rows *r-1* and *r* of that column;
    bottom edge moved (not the last row) → divider between *r* and *r+1*. A divider move
    re-splits the two rows' combined weight in proportion to their new heights, clamped so
    neither row drops below a minimum (e.g. 10% of the pair, mirroring `ratioRange`);
  - nothing applicable changed → `nil`. The ratio goes through the existing clamp/rounding.
- `Workspace` (`Workspace.swift`): `mutating func resize(_ windowID: WindowID, to frame:
  CGRect, in area: CGRect) -> Bool` — looks up the index, asks `layout.layout`, stores the new
  parameters, returns whether they changed.
- `SavedState`: `SavedWorkspace` gains optional `rowWeights: [[Double]]?` (decodes old files
  without it; no version bump), restored in `stack(count:keeping:)`.

### TylerServer
- New `PointerInput` protocol (`WindowBackend.swift` or its own file), `@MainActor`:
  `var events: AsyncStream<PointerEvent>`, `var isPrimaryButtonDown: Bool`, `start()`, `stop()`.
  `PointerEvent` has one case for now: `primaryButtonReleased(at: CGPoint)` (AX coordinates).
  `WindowManager.init` takes an optional `pointer: (any PointerInput)?` (nil = no mouse
  support, so existing tests and callers are unaffected); a second pump task, like `pump`.
- New `WindowManager+Mouse.swift` holding a `MouseDrag` state (`var drag: MouseDrag?`: the
  window id, and whether it is a resize or a move):
  - `apply(.updated(info))`: if running, tiling on, no animation, button down, and the window
    is tiled on the current workspace:
    - no drag yet and the frame isn't its slot (reuse `isInPlace`) → start a drag for this
      window; **only this window's updates count until release**, so the neighbours' echoes
      from tylerd's own `setFrame` during the drag are ignored.
    - size differs from the slot → `workspaces.current.resize(...)`; if the parameters changed,
      place every *other* window that isn't in place (never the dragged one: that would fight
      the drag).
    - size unchanged → move; nothing happens until release.
  - release: if a drag is active and its window is still on the current workspace,
    `applyLayout()` (snaps the dragged window to its exact slot, and a moved window back;
    swap-by-drag will hook in here using the location); clear the drag.
  - Commands (`beginCommand`), `tiling off`, workspace switches and the window's destruction
    clear the drag.
- Update the `WindowManager` header comment: resizes with the mouse button down now re-tile.

### TylerPlatform (thin, not unit tested)
- New `PointerMonitor: PointerInput`: `isPrimaryButtonDown` = `NSEvent.pressedMouseButtons & 1
  != 0`; `start()` adds `NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp)` yielding
  `.primaryButtonReleased(at:)` with `NSEvent.mouseLocation` converted to AX coordinates (flip
  against the primary screen height, as `SystemProviders` does for displays); `stop()` removes
  it. Main thread; no GCD. `tylerd/main.swift` creates it and passes it in.

### Risks to watch in the live check
- Live following costs one AX round trip per neighbour per resize notification; with slow
  apps the main actor may fall behind. If it lags, coalesce (only act on the newest update
  per pump turn) — decide after measuring, not up front.
- An app that clamps a neighbour's size while the button is down is filtered by the
  one-window-per-drag rule; a drag that *starts* with a clamp echo would be misread (unlikely:
  tylerd only places windows mid-press during a drag).
- The ratio's 3-place rounding may leave the column edge ~1–2 pt off the cursor; snapped on
  release.

## Increments (one commit each, `make test` + lint passing)
1. Save this plan as `plans/mouse-resize.md`; in `devdocs/ROADMAP.md` add a "Mouse
   resizing" section (decisions + checklist), and short entries for the long-term items:
   swap by drag and drop, grid layout, strip layout (with the `Layout` protocol open item),
   and trackpad swipes (folded into M7).
2. TylerCore: `rowWeights`, `ColumnLayout` frames with weighted rows, `TallLayout` on top of it,
   `SavedState` field. Tests: equal weights = today's frames; uneven weights; weights
   longer/shorter than the column; gaps; saved state round trip and decoding an old file.
3. TylerCore: `Layout.parameters(afterResizing:...)`, `ColumnLayout` inference,
   `Workspace.resize`. Parameterized tests: left column right edge, right column left edge,
   row top/bottom dividers, clamping, outer/immovable edges → nil, `full` → nil,
   single window → nil.
4. TylerServer: `PointerInput`, `PointerEvent`, `WindowManager+Mouse.swift`, `FakePointer` in
   `Fakes.swift`. Tests in `Tests/TylerServerTests/MouseResizeTests.swift`: master resize moves
   the stack live and never the dragged window; stack divider; neighbour echoes ignored; move
   snaps back on release; resize snaps the dragged window on release; no button down → nothing
   (today's behaviour); no pointer input → nothing; tiling off, floated window, running slide,
   non-current workspace → ignored; drag cleared by a command.
5. TylerPlatform: `PointerMonitor`, wired in `tylerd`.
6. Docs: `docs/manual.md` (Concepts: resizing with the mouse), roadmap ticks and log entry.

## Verification
- `make test`, `swift format lint --recursive --strict Sources Tests Package.swift`,
  `TOOLCHAIN_DIR=/Library/Developer/CommandLineTools swiftlint --strict` after each increment.
- After 5: `make build`, `tyler restart`, then the `live-check` skill with 3 windows in `tall`:
  drag the master's right edge (stack follows live), drag a stack window's left edge, drag the
  divider between the two stacked windows, drag the master's top edge (snaps back), move a
  window by its title bar (snaps back), check `tyler list` frames afterwards, and
  `tyler restart` keeps the row heights. Ask the user to do the drags if the skill can't
  drive the mouse; tick the roadmap checklist only for what was seen.
