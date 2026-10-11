# Plan: strip layout (niri-like)

> This is the plan the strip was built from, kept as written. For the strip as it is now (experimental), see `devdocs/strip-layout.md`.

## Context

The roadmap's "Later: strip layout": a workspace becomes one long horizontal strip of windows that scrolls left and right, each window with its own size. The `Layout` protocol only gets a window count, so it has to be reworked first (roadmap open item; REFACTORING item 11 steps 2–3 were deferred to this). The trackpad swipe was layered (pan → snap → target) so the strip can be a second `PanTarget`.

Decided with the user (2026-10-11):
- **Auto-pack by size.** The xmonad list stays the only model. Each window has a size preset; consecutive quarter windows share a column. No column commands.
- **Sizes: `full` (1 × 1), `half` (½ × 1), `quarter` (½ × ½).** New windows are `half`, so two windows look like `tall` at 50%.
- **Scroll just enough to fit** the focused column (niri's default). Focusing a window already in view doesn't scroll.
- **On a strip workspace the swipe scrolls only the strip**, never switches workspaces. Leaving a strip workspace takes `tyler workspace …` (a hotkey) or focusing a window elsewhere.

## Design

**Column packing (TylerCore, pure).** Walk the list in order: `full` and `half` each make a column of one; two consecutive `quarter`s make one column (top, bottom). A lone `quarter` fills its column's height (behaves as `half`; see caveats). Column widths: `half` = (W − 2·outer − inner)/2, `full` = W − 2·outer, with `IntegerBox.split` so two halves meet exactly like `tall`.

**View.** With only ½ and full widths, a "fit" scroll always leaves the view starting at a column boundary, so the view is stored as an **anchor window** (the first window of the leftmost visible column), not points. That survives display, gap and Dock changes. After any change (focus, insert, remove, resize, swap) the anchor is adjusted the least amount that keeps the focused column fully in view, and clamped so the view never shows empty space past the strip's end.

**On-view vs off-view.** At rest every column is either fully in view or fully out. Off-view windows **park at the right edge** like inactive workspaces' windows (`Parking.frame`), because macOS won't take a window further off-screen than 1 pt, and the left edge leaves a 56-pt strip beside a left Dock.

**Layout protocol rework.** Replace `frames(count:in:parameters:)` with `frames(for input: LayoutInput, in area: CGRect, gaps: LayoutGaps)`, where `LayoutInput` carries the count, per-window sizes, the focused index, the view anchor and the per-workspace parameters (ratio, row weights). `tall`/`full` ignore what they don't use. Gaps leave `LayoutParameters` (REFACTORING 11.3), which ends `setGaps` being pushed into every workspace. 11.2 (column weights in `ColumnLayout`) stays deferred: the strip doesn't resize columns by mouse yet.

**Workspace API.** `Workspace.placements(in:)` keeps returning only windows in view, so drop targets, `slot(of:)`, `currentPlacements()` and the slide's entering set work unchanged. A new `offView(in:) -> [WindowID]` lists the rest. Sizes live in `Workspace` (`sizes: [WindowID: WindowSize]`, default `half`) and travel with a window on `WorkspaceStack.move`.

## Branch and worktree

**All strip work happens in a separate git worktree at `../tyler-strip`**, on a **feature branch `strip-layout`** made from `main` (`git worktree add -b strip-layout ../tyler-strip main`). Every edit, build, test and commit for this feature runs there. Nothing changes in the main checkout, which stays on `main` for the other agent. That's an exception to CLAUDE.md's "commit directly on `main`", for this feature only. The CLAUDE.md line stays as it is.
- One commit per increment on the branch, the pre-commit hook as usual (never `--no-verify`).
- The other agent keeps committing to `main`. **Rebase `strip-layout` onto `main` before each increment** so its refactorings land under the strip work early, not all at once at the end. Re-run `make test` after each rebase.
- Docs conflicts: `ROADMAP.md`, `REFACTORING.md` and the CLAUDE.md status line change on both branches. Keep strip edits to them in their own sections or lines (a new "Strip layout" roadmap section, ticking 11.3) so rebases stay simple.
- When step 8 is done, ask the user before merging. The plan is a fast-forward merge into `main` after a final rebase. Nothing gets pushed.

## Increments (one commit each on `strip-layout`, `make test` + lint, roadmap ticked as they land)

0. **Create the branch in its own worktree** (`git worktree add -b strip-layout ../tyler-strip main`) **and write the plan into it:** `plans/strip-layout.md` (this content) and a strip section in `devdocs/ROADMAP.md` with a checklist; resolve the open item about the `Layout` protocol there.
1. **Pin behaviour** that step 2 touches, if not already covered: gaps on reload reaching every workspace, ratio/row weights surviving a gap change, `SavedState` round trip of parameters. Check each new test can fail.
2. **Layout protocol rework** (`Layout.swift`, `Layouts.swift`, `Workspace.swift`, `WindowManager+Config.swift`, `SavedState.swift`): `LayoutInput`, `LayoutGaps`, no behaviour change, no test changes except setup. Tick REFACTORING 11.3.
3. **TylerCore: sizes and `StripLayout`.** `WindowSize` enum, `Workspace.sizes` + `setSize(_:of:)`, carried by `WorkspaceStack.move`; `StripLayout` (packing, strip-coordinate frames, anchor → offset, fit rule, end clamp). Parameterized tests: packing (lone quarter, quarter pairs broken by a half), gaps, fit left/right, clamp at the end, anchor window removed. Not yet a `LayoutKind` case, so `layout next` can't reach a half-built layout.
4. **TylerCore: view state.** `Workspace.anchor`, updated in `setFocus`/`focus`/`swap`/`insert`/`remove`/`sync`; `offView(in:)`. `WorkspaceSync.Marks` gets the current workspace's off-view windows (like `sliding`), so a parked strip window isn't dropped for overlapping a neighbouring display. `SavedState` carries sizes and the anchor (optional fields, old files still load).
5. **Server: `LayoutKind.strip`** (symbol for the menu bar, cycled by `layout next`). `applyLayout` parks off-view windows; a focus change to an off-view window of the current workspace (click, cmd-tab) scrolls to it; scrolling **jumps** in this step. `tyler size full|half|quarter|next` through the `CommandSpec` table and `docs/manual.md` (stored in any layout, only the strip uses it; the reply says so). Workspace slides leave off-view windows parked (they must not get an entering track, or they would flash across from the left). Tests with `ManagerHarness`; `live-check` stacking.
6. **Animated scroll.** A scroll track per window whose path crosses the view, x clamped by `Parking.allowedX`; windows entering from the left first jump from the right-edge park to hanging off the left edge (`SlidePlan.start` does the same). Runs through `Animator`/`Interaction.sliding`, so commands mid-scroll finish it like a slide. `live-check` replay.
7. **Swipe.** `PanTarget.strip(…)` in `WindowManager+Pan.swift`: offset in points (travel / `swipe-distance` × view width), snap points = every column boundary the view can start at, `Snap.resisted` past the ends (a strip that fits the view only rubber-bands). On a strip workspace the swipe never selects the workspace row. Checked against real windows by the user.
8. **Docs:** manual (Concepts: strip, sizes; `layout strip`, `size`; the swipe on a strip workspace), roadmap ticks and log, CLAUDE.md status line.

Later, not in this plan: mouse resizing in the strip (an edge drag picks the nearest size, or free widths), drag-to-swap across off-view columns.

## Caveats

- **Another agent is refactoring in parallel** on `main`. By the time this branch was made (`1f7b37c`) it had finished REFACTORING items 8, 17 and 19; `Snap.resisted` stayed public and `LayoutParameters.withGaps` still exists. The remaining overlap is item 11 (steps 2 and 3, now step 2 here) and item 14 (renames `WorkspaceStack` → `WorkspaceRow`, `init(stack:)`). Before step 2, agree that the other agent leaves item 11 alone, and ideally lands item 14 first (a pure rename is cheaper before than after). Overlapping edits show up as rebase conflicts in `Layout.swift`, `Workspace.swift`, `SavedState.swift` and `WindowManager+Pan.swift`. Re-read files after every rebase.
- **The worktree.** The main checkout stays on `main` for the other agent, so the strip work runs in `../tyler-strip` with its own `.build`. `tyler restart` for live checks must use that worktree's `.build/debug/tylerd`, and only one `tylerd` can own the socket at a time, so live checks need to be coordinated with the other agent too.
- **Parking makes the strip "pages", not a continuous canvas.** At rest off-view windows sit as 1-pt slivers at the right edge; niri's peeking neighbours aren't possible at rest. During a scroll from the right they slide in smoothly; from the left they first appear beside the Dock (the same 56-pt strip the workspace slide shows).
- **Swipe trap.** On a strip workspace the swipe can't switch workspaces; if swiping is your only workspace switcher, you need a hotkey for `tyler workspace`. Many off-view windows also mean many AX writes per scroll frame on slow apps (same limit as slides).
- **Lone quarter.** A lone `quarter` fills its column's height rather than leaving the bottom half empty (an assumption, not yet confirmed by the user). Easy to change in step 3.
- **App minimum sizes.** Quarter windows (½ × ½) may be below some apps' minimum height; macOS then clamps and the column won't line up. Terminals snap to character cells.
- **`ratio` and row weights** don't apply to the strip (`ratio` answers that it has no effect there). Mouse resizing is off in the strip until the later slice; dragging an edge snaps back.
- **Focus-follows-mouse** (`plans/focus-follows-mouse.md`, untracked) would scroll the strip whenever the pointer crosses into a partly visible column mid-scroll; check the two together once both exist.
- **Multi-display (M5)** is still unsolved for parking; the strip adds more parked windows but no new problem.

## Verification

- Every step: `make test`, `swift format lint --recursive --strict Sources Tests Package.swift`, `TOOLCHAIN_DIR=/Library/Developer/CommandLineTools swiftlint --strict` (pre-commit runs all three).
- Steps 5–7: `make build && tyler restart`, then `tyler layout strip` with 3–4 windows; `tyler size full|quarter`, `tyler focus next/prev` past the view's edge, click a parked window's sliver, `tyler workspace next` and back, `tyler restart` keeps sizes and view. Use the `live-check` skill (stacking, replay) after each, and record results in the roadmap checklist before ticking anything "checked against real windows".

## Detailed design for steps 3–7 (worked out 2026-10-11, before any code)

- **Columns** (`StripColumns`, internal, TylerCore): window indices per column, widths in halves (half 1, full 2, quarter pair 1, lone quarter 1). `visible(from: s)` is the longest run from column `s` whose widths add up to at most 2. `fittedStart(previous:focused:)`: a focused column left of the view becomes the start; one right of it gives the smallest start whose run still reaches it. Then the end clamp: while the run reaches the last column and one more column to the left still fits, move the start left. The snap points (view starts) are the starts the end clamp leaves where they are.
- **Frames** (`StripLayout: Layout`; `LayoutInput` gains `sizes: [WindowSize]` and `firstVisible: Int`, a window index): `u` is a position in halves relative to the view. A page is `box.width + inner` wide, and the second half starts at `IntegerBox.split(... weights: [1, 1])[1].origin`, so a view looks exactly like `tall`. Columns left of the view are contiguous at negative `u`. Columns after the visible run start on the next page (`u = 2 + …`). A frame counts as **visible when its centre is inside the area**.
- **Workspace**: `sizes: [WindowID: WindowSize]` (default half; `remove` forgets it, `WorkspaceRow.move` carries it). `firstVisible: WindowID?`. A private `refitView()` runs at the end of `insert`, `append`, `remove` (a removed anchor passes to the window that takes its place), `sync`, `setFocus`, `focus`, both `swap`s and `setSize`. New methods: `arrangement(in:gaps:)` returns every frame; `placements` returns only the visible ones; `offView`; `restingPlacements(on:gaps:)` gives the visible windows their slots and the rest parked frames; `stripViews(in:gaps:)` gives each snap point's offset in points, its anchor and its arrangement; `scroll(toFirstVisible:)` moves focus to the nearest visible column if the focused window left the view.
- **ScrollPlan** (TylerCore, like `SlidePlan`): built from the arrangements before and after a change. Windows visible at either end get a `Track` clamped by `Parking.allowedX`. `start` holds the windows that weren't visible before. `finals` and `returns` park whatever is off view at that end. `placements(at:)` serves the pan.
- **Server**:
  - `applyLayout` places `restingPlacements`.
  - `slidePlan`'s leaving set must be **visible windows only**, or parked strip windows would flash across from the left.
  - `syncWorkspaces` adds the current workspace's off-view windows to `Marks.sliding`.
  - A `updatingStripView { … }` helper captures the arrangement before a change and animates a `ScrollPlan` if `firstVisible` moved. It is used by `focus`, `swap`, `size` and `focusChanged` on the current workspace. A focus echo must **not** fall back to `applyLayout`, or it fights a running scroll.
- **Pan**: `PanTarget.strip`. The position in points is the view's offset minus `travel / swipeDistance × width`, clamped to the first and last snap points (no rubber band at first). The segment between neighbouring snap points gets one `ScrollPlan`. When the segment changes, park the old plan's windows that aren't in the new plan, and place the new plan's `placements(at:)`. On release: `Snap.target`, then `scroll(toFirstVisible:)`, focus if it changed, and `animate` from the current progress. Abandoning puts back the start view's resting placements. A strip workspace never switches workspaces by swipe.
- **Command**: `Request.size(SizeChoice)` (`set(WindowSize)` or `next`), a `CommandSpec` like `layout`, a `### size` section in the manual (a test checks it exists), and `LayoutKind.strip` with a symbol (for example `▤`).
