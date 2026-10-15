# Animate the re-tile when a window leaves the workspace

## Why

When a window leaves the current workspace (`tyler window move --to-workspace` without
`--follow`, a close, a minimize, its app quitting, a float), the windows that stay jump to their
new slots; only a window sent away slides. `window swap`, `promote` and `demote` already animate
their re-tile, and a window leaving should look the same.

A new setting, `animations.retile` (milliseconds, 0 to 1000, 0 jumps, default 250), sets how long
it takes. A new window opening still jumps; that can be its own piece of work later.

## What it reuses

- `Transition(retiling:to:duration:)` (`TylerCore/Motion/Transition+Retile.swift`): tracks from
  old slots to new ones, sizes included, leaving out windows whose slot stays.
- `TilingController.retiled(from:_:)`: the swap's path, `.animate` when there are tracks and
  `.reconcile()` when not. No reconcile follows the animation: its finals are the end state.
- `WindowManager.animate`: one slide at a time; a new one ends the running one first.
- `WorkspaceController.slideOut`: the sent window's track off the display and its parking spot.

## Increments

1. **`animations.retile`** in `Config.Animations`, with its tests and the manual's settings table.
2. **A window leaving re-tiles with an animation.** `TilingController.reconcile(model:)` takes the
   focused workspace's slots before the sync. When the focused current workspace only lost
   windows, isn't in a scrolling layout and nothing arrived for the focus, the windows that stay
   slide from those slots to their new ones instead of jumping. Scenario tests: closing one of
   three windows animates the other two; `retile = 0` jumps; the strip still jumps; a new window
   still jumps.
3. **Sending a window away re-tiles with an animation.** `moveToWorkspace` without `--follow`
   from the current workspace builds one transition: the sent window's track off the display and
   the others' tracks to their new slots (only one slide runs at a time, and a reconcile after it
   would make the others jump). It takes `animations.retile`; with 0 the window slides away as
   now and the others jump. On a display with a neighbour beside it the sent window jumps to its
   parking spot while the others still slide. Scenario tests in `MoveToWorkspaceScenarios`.
4. **Docs and review**: the manual (`window move`, `window close`), `devdocs/design.md`,
   `devdocs/testing.md`, then a review of the whole diff.

## Caveats

- A second window leaving during the animation ends the first (its windows jump to their
  finals), then animates from the slots. Starting from slots rather than reported frames keeps
  this consistent: reported frames lag behind the window events.
- In the strip a window leaving changes the view; that stays a jump.
- Apps that resize slowly may lag while every frame resizes them, as in a swap.
- A window leaving the current workspace of a display that isn't focused still jumps (the sync
  lays those displays out).
