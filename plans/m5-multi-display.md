# M5: Multi-display, implementation plan

The first increment copies this plan to `plans/m5-multi-display.md`, as CLAUDE.md asks.

## Context

tyler tiles only the primary display today:
- one `WorkspaceRow` (`WindowManager.workspaces`);
- `primaryDisplay = displays.displays.first` (`WindowManager+Placement.swift:11`), used in about 15 places;
- `WorkspaceSync.plan`, which only tiles windows on the primary display;
- saved state that holds one row.

Windows on the Dell are left alone. M5 gives each display its own row of workspaces, its own layouts, swipes, drag across displays, display commands, and a menu bar map that follows the focused display. The work is big, so it goes on the branch `m5-multi-display` in the worktree `../tyler-m5`. Rebase it onto `main` before each increment, and merge with `--ff-only` at the end.

**The user's setup** (measured 2026-10-11):
- The laptop is the primary display, at AX (0,0,1800,1169). The Dock is on the left, so the visible frame starts at x = 55.
- The Dell U2717D is 2560×1440 and sits **above** the laptop, at AX (−397,−1440).
- "Displays have separate Spaces" is **off**, so there is one menu bar, on the laptop.

## Decisions

1. **Global workspace numbers.**
   - Each workspace belongs to one display.
   - A display's row is its workspaces, **always sorted by number**.
   - `workspace 5` switches to 5 on the display that holds it, and makes that display the focused one.
   - `prev` and `next` stay within the focused display's row.
2. **Config: an explicit list per display.**
   ```toml
   [displays]
   1 = [1, 2, 3, 4]
   2 = [5, 6, 7, 8, 9]
   ```
   - **Without `[displays]`**, each display gets `workspaces.count` workspaces, numbered on from the previous display: display 1 gets 1…count, display 2 gets count+1…2·count. With one display this is exactly today's behaviour.
   - **A connected display that isn't listed** gets `count` new workspaces, numbered after the highest existing one.
   - **Validation errors:** a key that isn't a whole number ≥ 1, an empty list, a list longer than 10, a number outside 1…99, a number listed twice.
   - **`[assign]` numbers are global.** With `[displays]` set, an assigned number must be one of the listed ones.
3. **Display numbering.** The primary display (the one with the menu bar) is 1. The others follow left to right, then top to bottom.
4. **Commands act on the focused display.**
   - The focused display is the one of the focused window.
   - tylerd also remembers the display a command last targeted, so switching to an empty workspace keeps its display.
   - **Swipes** act on the display under the pointer, and make it the focused display.
5. **Each workspace keeps its own layout.** This is already true per `Workspace`. Layout commands now hit the focused display's current workspace.
6. **Drag across displays.**
   - The window joins the target display's current workspace at the slot under the pointer, and the window there moves one place later.
   - On an empty spot, or an empty workspace, it goes last.
   - The decision is made on release. The window no longer leaves its list in the middle of the drag.
7. **A window that changes display any other way** (the Window menu, Rectangle, a resolution change) goes last in the current workspace of the display it is now on. Today it is left untiled.
8. **Disconnect and reconnect.**
   - A display's workspaces join display 1's row, in number order.
   - When the display comes back, its workspaces return to their **home**. A workspace's home is the display the config gives it, or the display it was last moved to with `move-workspace-to-display`.
9. **Indicator.**
   - "Separate Spaces" stays off. tylerd warns in its log and in `tyler status` when that setting is on.
   - The map and the text item show the **focused display's** row and switch when focus moves.
   - A click on the map sends the global workspace number.
   - Different content on each display's menu bar is not possible through the public API: the copies on other displays are an `NSStatusItemReplicant` kept in step with the original.
10. **Side by side is supported.**
    - Each display parks windows at an edge that touches no other display: right if free, otherwise left.
    - **Nothing crosses onto another display** (changed after spike S3: Dell windows sweeping across the laptop were distracting, and macOS shrank them to the laptop's height).
      - Slides keep the page direction. A window whose path would cross onto a neighbour jumps straight to its end instead (it vanishes into its parking spot, or appears in its slot). The others still slide.
      - On the Dell with the laptop to its left: `next` makes the outgoing windows vanish while the incoming ones slide in from the right; `prev` slides the outgoing ones out to the right while the incoming ones appear in place.
      - Swipes follow the same rule.
      - If the half-animated switch looks wrong in the live check, the whole switch goes instant instead.
    - The middle display of three has no free edge. The fallback (right edge or the bottom strip) is decided by spike S3.
11. **New commands.** `prev`/`next` wrap; `<n>` is a display number.
    - `tyler display <n|next|prev>` focuses that display's current workspace. The pointer doesn't move.
    - `tyler move-to-display <n|next|prev> [--follow]` puts the focused window into the target display's current workspace, after its focused window. Focus stays on the source display unless `--follow` is given.
    - `tyler move-workspace-to-display <n|next|prev>` moves the current workspace into the target display's row, sorted by number, and makes it current there. The source display shows its next workspace (or the previous one if there is no next). The workspace's home becomes the target. The command is refused if it would leave the source display with no workspace.
12. **Saved state version 2** holds one row per display, plus homes and the focused display. Version 1 files are still read, as display 1's row. Older builds can't read version 2; CLAUDE.md's "One tylerd at a time" gets a note about this.

## Data model (TylerCore, pure and unit tested)

- **`Display.swift`**
  - New `DisplayKey` (a string: UUID or `CGDirectDisplayID`, decided by S2).
  - `DisplayInfo` gains `key` and `parkingEdge`, both defaulted so existing callers still compile.
- **New `DisplayArrangement.swift`**
  - `ordered(_:)` sorts displays: primary first, then by `(minX, minY)`.
  - `parkingEdges(_:)` sets each display's parking edge.
  - The manager reads displays only through one helper, `connectedDisplays`, which applies both.
- **`Parking.swift`**
  - New `ParkingEdge { right, left }`.
  - `frame(for:on:)` uses the display's edge; the left edge is `visibleFrame.minX − width + 1`.
  - `allowedX` doesn't change.
  - `Track.leaving`/`entering` already clamp to `allowedX`, and `SlidePlan.start` already moves entering windows to their start.
  - Avoiding the crossing: `SlidePlan` gets the display's neighbouring sides, and a track heading through a side with a neighbour becomes a jump (start equals end).
- **`WorkspaceRow`**
  - New `numbers: [Int]`, kept parallel to `workspaces`.
  - New mutators: `init(numbers:)`, `insert(_:number:)` (keeps the row sorted), `remove(number:)`, and `setNumbers(_:)`, which generalises `setCount`.
  - `index(of: .number(n))` looks the number up in `numbers`.
- **New `DisplayRows.swift`**
  - Holds one row per connected display, in display-number order.
  - `homes: [Int: WorkspaceHome]`, where `WorkspaceHome` is `.configured(displayNumber)` or `.pinned(DisplayKey)`.
  - The current workspace of each display that has left, so it comes back when the display does.
  - `focusedKey`.
  - Lookups: by workspace number, by window, and every window on every display.
  - Changes: `reassign(to:configured:)` (returns which workspaces moved where), `moveWorkspace(number:to:)`, `focus(_:)`.
- **`WorkspaceSync.plan`** works over every row:
  - A newcomer joins the current workspace of the display it opens on, or the workspace `[assign]` gives it, wherever that workspace lives.
  - A window on a display's current workspace that moves to another display changes rows, unless it is sliding or held by a drag (a new `Marks.held`).
- **`IndicatorSnapshot`**: the `row` and `area` of the focused display, plus `displayNumber` and `displayCount`.
- **`SavedState`**: version 2 as in decision 12.
- **Server side**
  - `WindowManager.rows: DisplayRows` replaces `workspaces`. During the refactor, `workspaces` stays as a forwarding accessor to the focused row.
  - New `WindowManager+Displays.swift` holds the display commands, the reconfiguration handling and `display(for:)`.
  - `DisplayProvider` gains `changes: AsyncStream<Void>`, fed from `didChangeScreenParametersNotification` (async, no GCD).
  - `PointerEvent.pan` carries the pointer location. In `SwipeTap`, use `CGEvent.location`, falling back to `NSEvent.mouseLocation`.

Existing code to reuse:
- `DisplayGeometry.display(containing:in:)` and `axRect`
- `Parking.allowedX`
- `SlidePlan` and `Track`
- `Workspace.dropTarget(for:at:among:)`
- `WorkspaceRow.setCount`'s merge logic
- `ManagerHarness` and `FakeDisplays.secondary`; make it match the Dell above the laptop, and add left and right neighbours

## Increments

Each increment is one commit, passes `make check` and updates its docs. The live checks use `devtools/live-check`. **Agree with the other agent before restarting `tylerd`.**

0. **Docs only.** Write `plans/m5-multi-display.md` and rewrite the roadmap's M5 section (decisions, checklist, known limitations). Point the open item "Parking with several displays" at it, add the commands to the CLI target, and create the worktree.
1. **Spike S1: geometry** (devtools only).
   - `live-check displays` prints, for each display, its id, UUID, AX frame and visible frame, which one is primary, the separate-Spaces setting, and the display number and parking edge as tyler would compute them.
   - `positions --display <n>` measures the Dell's slivers, a window at negative y, and a laptop window placed past x = 1800.
   - Record the results in the roadmap.
2. **Spike S2: reconfiguration** (devtools only). `live-check display-events <s>` logs screen-change notifications, the reconfiguration callback, ids and UUIDs, and window frames after each event. The user unplugs and replugs the Dell, closes and opens the lid, sleeps and wakes, and rearranges the displays. The results decide:
   - how long to wait after the last event before placing windows;
   - UUID or id for `DisplayKey`;
   - where macOS moves the windows of a display that goes away.
3. **Spike S3: side by side** (devtools only; the user rearranges the displays). `slide --park left|right|bottom --display <n>`.
   - Does macOS accept a position that lies mostly on the neighbour?
   - Does it resize a window that crosses onto a display of a different height or scale?
   - How does the bottom strip look?
   - The user judges the look of the slide and picks the fallback for the middle display.
4. **Characterisation tests** (tests only). Pin today's single-display behaviour the refactor will touch:
   - the indicator's area;
   - arrivals parked on the primary;
   - a pan on the primary while the pointer is over the secondary;
   - the strip's and the mouse's area.

   Break the code on purpose to see each test fail.
5. **`DisplayKey` and `DisplayArrangement.ordered`** (pure). Tests: the Dell above the laptop, side by side in both orders, three in a row, stacked, ties. No change in behaviour.
6. **`WorkspaceRow.numbers`, used by the indicators.**
   - The indicators use it in `TextTitle`, `IndicatorMenu`, `WorkspaceMap` and `MapIndicator`.
   - The "does not exist" error lists the numbers.
   - Tests: a row numbered `[5, 6, 9]`, keeping the row sorted, merging, and a map click sending `.number(6)`.
7. **`DisplayRows`** (pure, not yet used). Tests:
   - disconnect and reconnect, with each display's current workspace remembered;
   - clamshell;
   - a pinned home that is gone, then comes back;
   - the focused display falling back to display 1;
   - `moveWorkspace` refusing to empty a row.
8. **Refactor: the manager holds `DisplayRows`.**
   - Still one row, on the primary.
   - `primaryDisplay` becomes `display(for:)`/`focusedDisplay`; `applyLayout`, `currentPlacements`, `slidePlan` and `show` take a display key.
   - **No test changes**, only setup.
   - Live check: `tyler list` and `live-check menubar` look the same before and after.
9. **Saved state version 2.** Tests: a round trip, a version 1 file read as display 1, a version 1 hand-over in the restart tests.
10. **`[displays]` in the config** (decision 2), with `reload` using `setNumbers`. Config and reload tests for every validation error. Manual: `[displays]`, global numbers, `[assign]`.
11. **`WorkspaceSync` over every row** (pure; the manager still passes one row). Tests:
    - a newcomer on display 2;
    - a window moved to display 2;
    - held and sliding windows stay;
    - an assignment to a parked workspace on display 2.
12. **Tile every display: the first visible change.**
    - `applyLayout` runs on each display.
    - Arrivals park on their own display.
    - `stop`, `unparkAll` and `list` cover every row; `list` gains a DISPLAY number column.
    - **Rewrite the two `TilingTests` about dragging to and from another display on purpose** (decision 7), and say so in the commit message.
    - New `MultiDisplayTests`.
    - Live check: windows on the Dell tile; `workspace 5` parks them at x = 2162; the laptop is unaffected; `tyler restart` keeps both rows.
13. **The focused display.**
    - Focus events and commands update it.
    - `prev`/`next` stay within its row.
    - `workspace <n>` and `move-to-workspace <n>` work across displays.
    - Cmd-tab to a parked window on the Dell shows its workspace there.
    - Tiling commands act on the focused display.
    - Live check: `workspace 5`, then `layout`, changes the Dell only.
14. **Reconfiguration.**
    - Debounce the `changes` stream with S2's delay, on the injected clock.
    - Then finish any animation and drag, run `reassign`, park the workspaces that moved, and place each display's current workspace.
    - Tests: disconnect, reconnect, clamshell, a change during a slide, a burst of events.
    - Live check by the user: unplug and replug, lid, sleep and wake.
15. **The indicator follows the focused display.** Test: the snapshot switches when focus moves to the Dell. Live check: `live-check menubar` after focus changes.
16. **Parking edge per display; no crossing onto a neighbour.**
    - Tests in `ParkingTests`, `SlidePlanTests` and `WorkspaceAnimationTests`:
      - a display that parks on the left;
      - on a display with a neighbour, the tracks heading through that side jump while the others slide, for `next` and `prev`;
      - parked windows moving when the arrangement changes.
    - Live check side by side:
      - `workspace next`/`prev` and swipes on both displays;
      - `stacking` shows no window on the neighbour, at rest or during a switch;
      - the user judges the half-animated switch.
    - Record in `devdocs/strip-layout.md` that the strip's off-view windows jump on a display that parks on the left.
17. **Swipes on the display under the pointer.** Pan and strip-pan tests with two displays. Live check: the user swipes on each display.
18. **Drag across displays** (decision 6). Its core (holding the window, the drop) was built right after increment 13, when the user hit the half-working version; what is left is the preview on the target display, if wanted.
    - `Marks.held` keeps the window in its list during the drag.
    - On release, insert before the window under the pointer (found with `dropTarget`), or append.
    - No preview on the target display in this version.
    - Tests: a drop on a window, on an empty spot, on an empty workspace, and no change of list mid-drag.
    - Live check.
19. **`tyler display`.** The request, the CLI table, protocol and command-line tests, and the exhaustive switches in `WindowManager.handle`. Manual section. Live check.
20. **`tyler move-to-display [--follow]`.** The same pieces, plus tests in the style of `MoveToWorkspaceTests`.
21. **`tyler move-workspace-to-display`.** Homes get pinned, and the command is refused when it would leave the source empty. Tests include a reconnect after a manual move. Live check, then `tyler restart`, which must keep the home.
22. **Wrap-up.**
    - Tick off the roadmap.
    - Open items: the middle display, the Dock on the left, the separate-Spaces requirement, the strip's jumps.
    - CLAUDE.md: status, the intro on parking edges, the Layout section (`DisplayRows`, `DisplayArrangement`, `WindowManager+Displays`), the state-file note.
    - Merge with `--ff-only`.

Increments 19–21 depend only on 13, so they could come straight after it if you want the commands sooner.

## Caveats and known limitations

- **No per-display menu bar content** through the public API, and the map relies on separate Spaces staying off.
- **The middle display of three** has no free edge. Until S3 decides, parked windows sit on the neighbour.
- **The Dock on the left:** parking on the left edge of the laptop leaves a 56-point strip of the window showing beside the Dock (measured in M4).
- **Side by side, half of each switch is instant**: the windows heading through the side with a neighbour jump instead of sliding. A later experiment animates snapshots in tylerd's own windows, clipped to the display (needs Screen Recording permission); if it works, it replaces the jumps.
- **A window that crosses onto a shorter display is cut to its height** by macOS (measured in S3). This matters when windows are moved between displays, so tylerd always sets the full frame.
- **Display numbers follow position.** A different external display in the same position gets the same number and the same workspaces.
- **Version 2 state files** can't be read by older builds.
- **All of tyler's windows on the Dell get tiled** as soon as increment 12 runs.

## Verification

- `make check` in every increment. Pure logic is covered in TylerCoreTests; the manager is covered with `ManagerHarness` and two or three `FakeDisplays`.
- `live-check` on real windows after every increment that moves windows: `displays`, `positions`, `stacking`, `slide`, `menubar`.
- The user checks with the Dell above the laptop (the default), and side by side for increments 3 and 16. Unplugging, the lid, and sleep and wake are checked for increments 2 and 14.
- Each roadmap checklist item is ticked only after its live check.
