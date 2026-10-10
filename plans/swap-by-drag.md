# Swap by drag and drop

## Context
Today a tiled window moved by its title bar snaps back to its slot on release
(`WindowManager+Mouse.swift`, `apply(_ event: PointerEvent)`). The roadmap's "Later: swap by
drag and drop" item replaces that: drag a tiled window onto another tiled window and the two
swap slots. The mouse-resize work left the seams for this on purpose: the release carries the
pointer location, pointer input is its own source (`PointerInput`), and the layout is a list of
slots, so the hit test is generic (works in `tall`, later `grid`; no per-layout code).

Decisions (2026-10-10, with the user):
- **Live preview**: while the dragged window is over another tiled window's slot, that window
  moves into the dragged window's slot; moving off it puts it back. Release completes the swap.
- **The pointer decides** the target: the slot under the pointer. A pointer in a gap, in the
  dragged window's own slot, or outside the tiled area means no target, and the window snaps
  back as today. In `full` every slot is the dragged window's own, so nothing swaps.
- **Floated windows** take no part (as dragged window or target).

Behaviour that follows from existing rules (no decision needed): row weights belong to slots,
so each window takes the size of its new slot; the dragged window keeps focus; resize drags
never preview or swap; only the primary display (M5 is not done).

## Design

### TylerCore (`Sources/TylerCore/Workspace.swift`, pure, unit tested)
- `mutating func swap(_ first: WindowID, with second: WindowID) -> Bool`: swaps two windows'
  positions in `windows`; false if either is missing or they're the same. Focus is untouched
  (focus follows the id, like the existing `swap(_ target:)`).
- `func dropTarget(for windowID: WindowID, at point: CGPoint, in area: CGRect) -> WindowID?`:
  from `placements(in:)`, nil if `point` is inside `windowID`'s own slot; otherwise the other
  window whose slot frame contains `point`; nil for gaps, outside, unknown window.

### TylerServer
- `PointerEvent` (`PointerInput.swift`) gains `primaryButtonDragged(location: CGPoint)`
  (AX coordinates). Using the pointer's own events, not the dragged window's moved
  notifications, keeps the preview independent of how often each app reports moves.
- `MouseDrag` gains `isResize: Bool` (set once an update shows a size change; a resize drag
  never previews) and `previewTarget: WindowID?` (the window shown in the dragged window's slot).
- `followDrag(of:)`: unchanged for resizes; marks `isResize`.
- `apply(.primaryButtonDragged(location))`: if a move drag is active and the guards of
  `followDrag` hold (running, tiling on, no animation, window still on the current workspace),
  compute `dropTarget`. If it differs from `previewTarget`: place the old target back in its own
  slot, place the new one in the dragged window's slot (via `place([...])`), store it. Only
  target changes move windows, so no throttle is needed. Echoes of these moves are already
  ignored (`followDrag` counts only the dragged window's updates).
- Release: for a move drag, recompute `dropTarget` at the release location (exact, even if
  no dragged event arrived); if there is one, `workspaces.current.swap(drag.windowID, with:)`;
  then `applyLayout()` as today (the target is usually already in place and skipped).
- `endDrag()` (commands, workspace switch, the dragged window destroyed) puts a moved preview
  target back in its slot when tiling still runs and it's on the current workspace, so a
  command mid-drag never leaves two windows in the wrong slots. The preview target being
  destroyed clears `previewTarget` (reconcile re-tiles anyway).
- Update the doc comments of `followDrag` / `apply(_:)` and the `WindowManager` header.

### TylerPlatform (`Sources/TylerPlatform/PointerMonitor.swift`, thin)
- The global monitor also matches `.leftMouseDragged` and yields `.primaryButtonDragged` with
  the location; the AX conversion moves into a private helper shared with the release.

## Increments (one commit each; `make test`, swift format lint, swiftlint passing)
1. Docs: copy this plan to `plans/swap-by-drag.md`; in `devdocs/ROADMAP.md` turn
   "Later: swap by drag and drop" into a section with the decisions and a checklist.
2. TylerCore: `Workspace.swap(_:with:)` and `dropTarget(for:at:in:)`. Parameterized tests in
   `WorkspaceTests.swift`: tall with 3 windows, pointer in each slot / in a gap / own slot /
   outside; `full` → nil; one window → nil; unknown id → nil; swap keeps focus and the other
   windows' order; swap with self or missing → false.
3. TylerServer + TylerPlatform (together: the new event case must be handled by the monitor's
   module to build cleanly): `PointerEvent.primaryButtonDragged`, `MouseDrag` fields, preview
   and swap in `WindowManager+Mouse.swift`, `FakePointer.drag(to:)` in `Fakes.swift`,
   `PointerMonitor` monitoring drags. Tests in new `Tests/TylerServerTests/DragSwapTests.swift`:
   release over another slot swaps (order and frames); preview moves the target into the dragged
   slot mid-drag; changing targets puts the first one back; back over the own slot / a gap puts
   it back; release in a gap snaps back with no swap; a resize drag never previews or swaps;
   `full` never swaps; a command mid-drag restores the target; floated window, tiling off,
   running slide → nothing; preview target destroyed mid-drag; the target's echo updates are
   ignored. Check `MouseResizeTests.aWindowMovedByItsTitleBarGoesBackOnRelease`: it releases at
   `.zero`, which must stay outside any other slot in `FakeDisplays.main` (pass the window's
   own slot location if not).
4. Docs: `docs/manual.md` Concepts ("Resizing with the mouse" gains a "Swapping by dragging"
   part; the snap-back sentence changes), roadmap ticks and a log entry; `CLAUDE.md` status line.

## Verification
- After each increment: `make test`, `swift format lint --recursive --strict Sources Tests
  Package.swift`, `TOOLCHAIN_DIR=/Library/Developer/CommandLineTools swiftlint --strict`.
- After 3: `make build`, `tyler restart`, then the `live-check` skill with 3 windows in `tall`:
  drag a stack window over the master (the master previews into the stack slot), over the other
  stack window, back to its own slot (preview undone), release over the master (swapped;
  `tyler list` slots and frames), release in a gap (snaps back), a drag in `full` (no swap),
  a resize drag still behaves. Ask the user to do the drags if the skill can't drive the mouse;
  tick the roadmap only for what was seen. Watch for: preview lag with slow apps (Firefox), and
  whether macOS fights the target being moved under a window being dragged.
