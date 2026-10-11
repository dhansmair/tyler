# tyler roadmap (working document)

Update this file as work progresses: tick off items, log decisions, and move open questions into the decisions log once they're settled. It's the source of truth between sessions.

## Goal
A personal macOS window manager in Swift, replacing AeroSpace/Amethyst for this workflow:
- **xmonad-style tiling.** Each workspace is an ordered list of windows with a clear prev/next and a master (the first window). Typical use is two windows side by side, sometimes one on the left and two stacked on the right. Layouts must be extensible.
- **Workspaces side by side in a row**, like pages. Move left and right between them with a snap. (They started as a vertical stack; macOS doesn't let windows leave through the top or bottom of the screen, so the row became horizontal in M4.)
- **Server plus CLI.** `tylerd` runs in the background, and `tyler` sends it commands.

## Decisions
- Scrolling between workspaces is CLI-driven in v1 (animated slide and snap). Trackpad scrolling with a modifier key comes later.
- New windows tile by default. Dialogs, sheets and apps listed in the config float. `float toggle` switches any window.
- Multiple physical displays, with **one row of workspaces per display**. Commands act on the focused display.
- Hotkeys are external (skhd, Karabiner, Raycast). tylerd has no hotkey code.
- Every component is unit tested with Swift Testing (`import Testing`). It ships with the Command Line Tools, and XCTest isn't available.
- The executables stay thin. Logic lives in libraries, and everything that touches macOS (AX, NSScreen, timers) sits behind a protocol so tests can use fakes.
- IPC: one newline-delimited JSON request and one response per connection over a Unix socket (`~/.tyler/tyler.sock`, override with `TYLER_SOCKET`).
- Workspaces work by parking windows of inactive workspaces just past the right edge of the display's visible frame, at their own height, with 1 point visible (a variant of the AeroSpace trick; see the M4 measurements for why the right edge).
- **Terminology (decided 2026-10-10, after M4).** *Display* is a physical screen (matches `CGDirectDisplayID` and System Settings). *Workspace* is a page in a display's row of workspaces, with its own tiling list, layout and ratio; M4 called it a "virtual monitor", and the code, CLI (`workspace`, `move-to-workspace`), wire format and `list` column (`WORKSPACE`) were renamed. *Monitor* isn't used, and *screen* only describes visibility ("on screen"). Avoid *space* (macOS Spaces). Workspaces are numbered per display (1 to n within each row, from the left), and commands act on the focused display. The per-display row is `WorkspaceRow` (it was `WorkspaceStack` until 2026-10-11, when "stack" stopped meaning the row); "stack" now means only the windows to the right of the master in `tall`, as in xmonad.

## Package layout
```
Sources/
  TylerCore/     pure value types and POSIX helpers: Protocol, Paths, UnixSocket, Window, Display, (later) Layout, Workspace, WorkspaceStack, Config, Parking, Animation
  TylerServer/   server logic behind protocols: CommandRouter, IPCServer, WindowManager, WindowRegistry, Backend protocols, (later) Animator
  TylerPlatform/ real macOS implementations, not unit tested: AXBridge, AppObserver, AXBackend, system providers, (later) display link
  TylerClient/   argv parsing, response formatting, socket client
  tylerd/        server executable (thin)
  tyler/         CLI executable (thin)
Tests/         one test target per library
```

## Milestones

### M1. Skeleton, IPC and test harness
- [x] devdocs/ROADMAP.md
- [x] Package with TylerCore, TylerServer, TylerClient, `tylerd`, `tyler`
- [x] `Request`/`Response` protocol and `Paths`
- [x] Unix socket helpers and `IPCServer` (stale-socket handling, single-instance check)
- [x] `tyler ping` → `pong`, usage errors, "tylerd is not running" error
- [x] Tests for protocol, sockets, router, IPC round trip, CLI parsing and output
- [x] Makefile (`build`, `test`, `install`). `make test` is needed instead of plain `swift test`: the Command Line Tools ship Swift Testing, but SwiftPM doesn't find it without extra framework/rpath flags, which the Makefile passes.
- [x] Verified: 28 tests pass (`make test`, about 3 s), and `tyler`/`tylerd` checked by hand (ping, no server, duplicate server, SIGTERM removes the socket)
- [x] `swift format lint --strict` and `swiftlint --strict` are clean, and a pre-commit hook (`.pre-commit-config.yaml`) runs both plus `make test` on every commit that touches Swift files. SwiftLint needs `TOOLCHAIN_DIR=/Library/Developer/CommandLineTools` when full Xcode isn't installed; `.swiftlint.yml` aligns it with swift-format.
- [ ] Stable code signing for Accessibility (**deferred to M2**, see open items)

### M2. AX spike and window discovery
`tylerd` keeps a live list of the standard windows on the current Space, and `tyler list [--json]` shows it. It does not move, resize, focus or raise anything (that's M3).

Built and tested:
- [x] TylerCore: `WindowID`, `WindowInfo`, `WindowKind.classify`, `DisplayInfo`, `DisplayGeometry` (AppKit→AX y-flip, window→display by overlap), `Request.list` / `Response.windows`
- [x] TylerServer: `WindowRegistry` (idempotent events), `WindowManager` (`@MainActor`), `WindowBackend` / `DisplayProvider` / `AccessibilityGate` protocols, async `CommandRouter`, async `IPCServer.Handler` with one blocking-to-async bridge
- [x] TylerClient: `tyler list [--json]`, text table and JSON output
- [x] TylerPlatform (new): `AXBridge`, `AppObserver`, `AXBackend`, `SystemAccessibilityGate`, `ScreenDisplayProvider`
- [x] `tylerd` runs a real `NSApplication` run loop (`.accessory`), polls for the permission and starts tracking once it is granted
- [x] 81 tests pass; `swift format lint --strict` and `swiftlint --strict` are clean
- [x] Verified by hand without permission: `ping` works, `list` and `list --json` exit 1 with the instructions, bad usage exits 2, SIGTERM stops `tylerd` and removes the socket

**Manually verified by the user (2026-10-08):** with Accessibility granted, `tylerd` and `tyler list` work well against real windows. The checklist below records which items were confirmed.

**Not verified by Claude (this session has no Accessibility permission):**
- [ ] The whole TylerPlatform layer had never run against real windows when it was written (the user has since run it, see above). The planned spike (confirm AX events arrive under `NSApplication.run()`, check what `kAXWindowsAttribute` returns) was skipped and the layer was written straight from the AX documentation.
- Manual checklist, with Accessibility granted to the terminal that runs `tylerd`. Confirmed by the user so far:
  - [x] `min` flag shows for a minimized window
  - [x] `full` flag shows for a fullscreen window
  - [x] `focused` flag follows focus
  - [x] closing a window removes it from the list

  Still unconfirmed:
  - [ ] opening a new window adds it
  - [ ] moving and resizing a window updates its frame (and the frame is in top-left coordinates)
  - [ ] quitting an app with several windows removes all of them
  - [ ] a Save panel shows as `dialog`
  - [ ] `DISPLAY` is right (only one display exists on this machine, so a second display can't be checked yet)
- [ ] Confirm `dispatchMain()` was really insufficient and `NSApplication.run()` is needed (not tested, I assumed it).

### M3. Tiling on one display
`tylerd` keeps an ordered list of tiled windows (xmonad style: the first is the main window, everything has a next and a prev), lays it out with `tall` or `full`, and is driven by CLI commands. This is the first milestone where `tylerd` moves your windows.

Decisions: tiling starts when `tylerd` has permission (kill switch: `tyler tiling off`); dragging or resizing a window by hand is left alone until the next re-tile (tiling reacts only to commands and to windows appearing, disappearing, or becoming un/tileable); one workspace on the primary display's visible frame; new windows go after the focused one; windows present at start are ordered left to right.

Built and unit tested:
- [x] TylerCore: `Layout` protocol, `LayoutParameters` (ratio clamped to 0.1…0.9, outer/inner gap), `TallLayout`, `FullLayout`, `LayoutKind`, `Workspace` (insert/remove/sync, focus and swap with wrap-around, ratio, layout cycle), command types, `slot` and `isFloated` on `WindowInfo`
- [x] TylerServer: `WindowBackend.setFrame` / `focus`, tiling in `WindowManager` (reconcile on events, skips windows already in place, one failing window never stops the others), router forwards every command
- [x] TylerClient: `focus`, `swap`, `layout`, `ratio`, `float toggle`, `tiling`, `retile`; `SLOT` column and `floated` flag in `list`
- [x] TylerPlatform: `AXBridge.setFrame` (size, position, size) and `raise`, `AXBackend.setFrame` / `focus`
- [x] 195 tests pass; `swift format lint --strict` and `swiftlint --strict` are clean
- [x] Verified by hand without permission: every new command exits 1 with the permission instructions (`tiling off` works), bad arguments exit 2 with the valid choices, SIGTERM stops `tylerd` and removes the socket

**Not verified (needs Accessibility permission, which Claude's session doesn't have):** the code that actually moves and focuses windows (`AXBridge.setFrame` / `raise`, `AXBackend.setFrame` / `focus`) has never run against a real window. Checklist for the user. Run `tyler tiling off` from a second terminal if anything goes wrong:
- [x] (2026-10-10, run by Claude with Accessibility granted) Windows at start tile: one left, the rest stacked on the right (5 windows seen)
- [x] `focus next|master` moves focus across apps (Ghostty to Code and back); the `focused` flag follows. `prev` and the actual keyboard/raise were not checked separately
- [x] `swap next|master`, `layout tall|full`, `ratio +0.05|-0.05`, `float toggle` (twice), `retile`, `tiling off` then `on` all behave. Not run: `swap prev`, `layout next`. Note: toggling float back on re-inserts the window after the focused one, so the old master lost its slot
- [x] Closing, minimizing and fullscreening a tiled window re-tiles the rest (2026-10-10, by the user: "window lifecycle works"). Dragging is now handled by mouse resizing (title-bar moves snap back)
- [x] The menu bar and the Dock side are respected (2026-10-10, macOS 26.7, Dock on the left: the visible frame starts at x = 55, y = 39, and tiles sit at 67,51 with `outer = 12`)
- [ ] A terminal (character-cell snapping) and a window with a minimum size (such as System Settings) end up where expected, and `list` shows their real frames
- [x] `list` shows sensible `SLOT` values and `floated`
- [ ] The size-position-size sequence in `AXBridge.setFrame` is actually needed (it is a common AX technique that I did not verify here)
- [ ] The frontmost-app plus raise approach in `AXBridge.raise` works for an accessory app like `tylerd` (I chose it because the SDK documents `NSRunningApplication.activate` as cooperative and not guaranteed)

### M4. Workspaces (workspaces) and the animation spike
Plan: `plans/m4-virtual-monitors.md`. A fixed stack of 4 workspaces on the primary display, `workspace prev|next|<n>` with a slide, `move-to-workspace`, focus-driven switching, and restore on exit.

Decisions (agreed in the plan): 4 workspaces (configurable in M6), primary display only (per-display stacks are M5); `prev`/`next` wrap (named `up`/`down` until 2026-10-10) and `<n>` is 1-based and range-checked; the animation is built in from the start and a snap is an animation with zero steps; on SIGINT/SIGTERM every window goes back to its original frame (crash recovery is out of scope). New windows (and windows that become tileable again, such as un-minimized ones) go to the current workspace. Floated windows and dialogs belong to no workspace and stay visible everywhere. Parked windows sit in the display's bottom-right corner with 1 point visible (changed after M4: see the horizontal slide below). A command arriving mid-slide jumps to the slide's end first. `workspace` and `move-to-workspace` need tiling on.

Decisions made while building (flag at review):
- **"Original frame" means the frame just before tylerd first moves a window**, not the frame when tylerd first saw it. Windows tylerd never moved (dialogs, windows already in their slot that never slid) are left alone on exit. For tiled windows the two are the same in practice.
- **`tiling off` empties only the other workspaces** (their windows go back to their original frames). The current workspace keeps its list, so `tiling on` restores its order as M3 did. The plan said all assignments are cleared; keeping the current one is what the existing M3 test expects.
- **tylerd ignores the echo of its own focus calls.** Each window tylerd focuses is remembered until its focus event arrives, and that event never switches workspaces. Without this, a quick `workspace next` then `workspace prev` could switch back when the first focus event arrives late.
- **Slide direction (changed 2026-10-10, see below):** `workspace next` moves the current windows out to the left by the width of the visible frame while the next workspace's windows come in from the right; `prev` is the reverse. The first version slid vertically, which macOS doesn't allow. `<n>` slides like `next` if n is after the current workspace. `move-to-workspace` without `--follow` slides only the moved window out, towards its workspace (right for `next`, left for `prev`: the opposite of windows leaving when the view scrolls, because here the window moves and the view stays); the rest re-tile at once.
- **No `Animator` protocol.** `Animator` is a struct with an injected `Clock`; the clock is the test seam (`TestClock` in the server tests). Default: 250 ms with frames on an 8 ms grid (at most 32 frames), each intermediate frame one `setPosition` per window, the last frame a full `setFrame`. Progress comes from the elapsed time, so a slow app makes the slide coarser but not longer; a frame that overruns skips the deadlines it missed.
- Replies: `workspace <n>`, `moved to workspace <n>`, `already on workspace <n>`.

Built and unit tested:
- [x] Phase 1, restore on exit: `WindowManager.stop()` cancels any slide and puts every window it ever moved back (failures logged, never blocking the rest); the `tylerd` signal handler already called it
- [x] TylerCore: `WorkspaceTarget`, `WorkspaceStack` (wrapping `prev`/`next`, range-checked numbers, `move`, per-workspace focus), `Parking`, `Track`/`Easing`/`ScrollDirection`, `WindowInfo.workspace`, `Request.workspace` / `Request.moveToWorkspace`
- [x] TylerServer: `WindowBackend.setPosition`, `Animator`, workspaces in `WindowManager` (`WindowManager+Workspaces.swift`): per-workspace membership (parked and sliding windows keep their workspace whatever their frame says), switching with a slide, `move-to-workspace [--follow]`, focusing a parked window switches to its workspace, `tiling off` unparks
- [x] TylerPlatform: `AXBridge.setPosition` (one AX write), `AXBackend.setPosition`
- [x] TylerClient: `workspace prev|next|<n>`, `move-to-workspace prev|next|<n> [--follow]`, `WORKSPACE` column in `list`
- [x] 255 tests pass; `swift format lint --strict` and `swiftlint --strict` are clean

**Not verified against real windows** (a user `tylerd` was running, and a second instance would fight it over the same windows). Checklist, with `tyler tiling off` or SIGTERM as the escape hatch:
- [ ] Windows return to their original frames after SIGTERM, including parked ones
- [x] `workspace next|prev|<n>` slides windows and ends with the right set visible; `workspace next` on the last wraps to the first (2026-10-10, by Claude with `tyler list`: 1→2→3→4→1 and `prev` from 1 to 4; how the slide looks was not judged)
- [x] New windows open on the current workspace; `list` shows the `WORKSPACE` column (2026-10-10, by the user)
- [x] Parked windows are really hidden (about 1 point visible) and macOS doesn't pull them back on screen (2026-10-10: parked at x = 1799 on the 1800-point display, still there after many switches)
- [x] Slide smoothness with 3+ windows: smooth with the horizontal slide (demo script, not yet tylerd itself)
- [x] tylerd's horizontal slide on real windows, both directions, and parked windows staying put as a 1-point column at the right edge (2026-10-10: the user judged `workspace prev|next` good)
- [x] macOS lets the outgoing windows slide up past the menu bar. If it clamps them, they bunch at the top for 200 ms; then slide them down instead, or park first
  - **Measured 2026-10-10 (macOS 26.7): it clamps, in every direction, for every app tried (Ghostty, Firefox, Edge, Code).** A position write with y above the menu bar lands at y = 39; one below the screen lands at maxY − 32; horizontally, a window must overlap the display's *visible frame* (Dock excluded) by at least 1 point: x = visibleMaxX − 1 and x = visibleMinX − width + 1 are accepted, and anything further snaps back to 40 points inside (with the Dock on the left, visibleMinX = 55, so the left limit leaves a 56-point strip beside the Dock). Parking at (maxX − 1, maxY − 1) therefore really ends at (maxX − 1, maxY − 32): a 1 × 32 point sliver. So a window can travel at most (y − 39) up or (maxY − 32 − y) down, and incoming windows placed a display height away start already on screen. That is why the slide is smooth for some windows (bottom row, moving down) and jumps for others. AX calls themselves are fast (1–3 ms per write), so speed is not the cause. The fix can't be AX-only for a vertical slide.
  - **Fixed 2026-10-10: the slide is horizontal.** The user rejected a snapshot overlay (it needs Screen Recording permission) and chose a horizontal slide after a throwaway demo on real windows (Ghostty ×2, Firefox out, Edge and Code in, 250 ms, about 65 frames per second, judged smooth). All windows move by the same page offset, and each window's x is limited to `Parking.allowedX` so macOS never pulls it back. Windows park at the right edge at their own height, so windows coming in from the right start where they wait. With the Dock on the left, windows leaving to the left stop as a 56-point strip beside the Dock before they park.
- [x] `move-to-workspace` with and without `--follow` (2026-10-10: without, the rest re-tile and the window parks; with, it lands after the focused window and the view follows)
- [ ] cmd-tab to a parked window switches workspace
- [ ] `tiling off` with parked windows leaves a usable screen
- [ ] Closing a window whose app has another window on a parked workspace: macOS may focus that parked window, and tylerd then switches to its workspace (likely unwanted; see open items)

### Menu bar indicator (added 2026-10-10, between milestones)
The user asked for a menu bar item after a window seemed lost behind another one on a workspace in the full layout. Decisions (agreed with the user): the workspace numbers with the current one in brackets and empty ones faint, such as `1 [2] 3 4` (changed the same day from one dot per workspace: `◉` current, `○` with windows, faint `○` empty), plus the current layout's symbol (`▥` tall, `▢` full); clicking opens a small menu with the workspaces, the layout and tiling. The menu sends ordinary `Request`s through `WindowManager.handle`, so it behaves exactly like the CLI.

- [x] TylerCore: `IndicatorState` (title parts, layout, menu items), unit tested
- [x] TylerServer: `Indicator` protocol; `WindowManager` pushes the state from `didSet` on `workspaces`, `tilingEnabled` and `state`, and only when it changed (`WindowManager+Indicator.swift`)
- [x] TylerPlatform: `StatusBarIndicator` (`NSStatusItem`); tylerd creates it before the manager
- [x] The item appears and its text follows workspace switches and `layout tall|full` (2026-10-10, `live-check menubar`)
- [x] Checked for real (2026-10-10, by the user): the menu bar item and its menu work
- [ ] Light and dark menu bar, and `tiling off`, not reported separately
- [x] Moved into the `TylerIndicators` target (2026-10-11, first step of the workspace map): the server hands every indicator an `IndicatorSnapshot` (the row, tiling, the display's area) through the `Indicator` protocol in TylerCore, whenever the snapshot changes. `IndicatorState` became `TextTitle` and `IndicatorMenu`; `StatusBarIndicator` became `TextIndicator`, which redraws only when its title or menu changed (focus and ratio changes reach it but don't redraw it)

### Mouse resizing (added 2026-10-10, between milestones)
Resizing a tiled window with the mouse moves the layout with it: in `tall`, the divider between the master and the stack, and the dividers between windows in the stack. Plan: `plans/mouse-resize.md`.

Decisions (2026-10-10, with the user): neighbours follow **live** during the drag; stack heights are kept **per slot** (a new slot gets weight 1); a window moved by its title bar **snaps back** on release, and so does any edge that isn't a divider. Designed with the long-term items below in mind: frames and resize logic are written once for "columns of rows" (`tall` is columns `[1, n-1]`, `grid` will reuse it), row weights are kept per column, the release carries the pointer location (for swap by drag), and pointer input is its own source (`PointerInput`, which M7's scroll and swipes will also use).

- [x] TylerCore: `rowWeights`, `ColumnLayout`, `TallLayout` on top of it, `SavedState` keeps the weights
- [x] TylerCore: `Layout.parameters(afterResizing:)`, `Workspace.resize`
- [x] TylerServer: `PointerInput`, `WindowManager+Mouse.swift` (the placing helpers moved to `WindowManager+Placement.swift` to keep `WindowManager.swift` under SwiftLint's 400 lines)
- [x] TylerPlatform: `SystemPointerInput`, then called `PointerMonitor` (global `leftMouseUp` monitor, button state)
- [x] Throttled (2026-10-10, after the user saw live following lag, worst with Firefox): the first resize of a drag is followed at once, then at most once per interval, always to the newest frame; the release follows the last one at once. Before, every resize event moved every neighbour, and slow apps let the events pile up. If it still lags, the next lever is `AXBackend.setFrame` re-reading the whole window (title, role, …) after every move. The interval is `mouse.follow-interval` in the config (milliseconds, 0–1000, default 50, 0 follows every resize; decided with the user 2026-10-10), read at every step so `reload` applies it at once
- [x] `restart` keeps the stack heights (2026-10-10: 708/390 before and after)
- [x] Checked against real windows (2026-10-10, by the user): resizing is smooth and the layout follows; live following keeps up with the 30 ms interval

### Swap by drag and drop (added 2026-10-10, between milestones)
Drag a tiled window by its title bar onto another tiled window and the two swap slots (replaces the snap-back). Works in every layout with slots, `grid` included. Plan: `plans/swap-by-drag.md`.

Decisions (2026-10-10, with the user): a **live preview**: while the dragged window is over another tiled window's slot, that window moves into the dragged window's slot, and moves back when the pointer leaves; the release completes the swap. **The pointer decides** the target (the slot under it); a pointer in a gap, in the dragged window's own slot or outside the tiled area snaps back as before, so `full` never swaps. **Floated windows** take no part. The pointer's position during the drag comes from a new `PointerEvent.primaryButtonDragged` (a global `leftMouseDragged` monitor), not from the dragged window's moved notifications, so the preview doesn't depend on how often an app reports moves.

- [x] TylerCore: `Workspace.swap(_:with:)`, `Workspace.dropTarget(for:at:in:)`
- [x] TylerServer: `PointerEvent.primaryButtonDragged`, preview and swap in `WindowManager+Mouse.swift`; a command mid-drag puts the preview back
- [x] TylerPlatform: `SystemPointerInput` reports drags (global `leftMouseDragged` monitor)
- [x] Checked against real windows (2026-10-10, by the user): preview, swap on release, snap back in a gap, `full`, resizing still works
- [x] Tried and dropped (2026-10-10, with the user): the dragged window taking the target slot's size during the preview (a size-only AX write, top-left corner kept). It worked, but the size jumped without animation and felt awkward. Animating it isn't practical: every step makes the app lay out the window again (the reason live following is throttled), and AX-based managers (AeroSpace, Amethyst) don't animate resizes either. The dragged window keeps its size until the release

### Later: grid layout
A new layout: the same as `tall` for up to 3 windows; 4 puts one window in each corner; 5 splits the right half in three; 6 splits both halves in three (2 columns × 3 rows). Beyond that more columns appear (for example 3 × 3 at 9; the exact rule is still open). Mouse resizing and swap by drag work here too, through the shared column model.

### Strip layout (experimental)
A niri-like layout: a workspace is one long horizontal strip of windows that scrolls left and right. Each window has its own size. **Experimental:** it works, but its design (quarters especially) is still open. Current state, known issues and open questions: `devdocs/strip-layout.md`. Plan: `plans/strip-layout.md`. Built on the `strip-layout` branch (in its own worktree) and merged into `main` on 2026-10-11.

Decisions (2026-10-11, with the user): the list stays the only model, and columns are packed from per-window sizes: `full` (1 × 1) and `half` (½ × 1) each make a column, two consecutive `quarter`s (½ × ½) share one. New windows are `half`. Focusing a window out of view scrolls just enough to show its whole column. Off-view windows park at the right edge like inactive workspaces' windows. On a strip workspace the swipe scrolls only the strip, never switches workspaces.

- [x] Tests pinning what the `Layout` protocol rework touches: gaps reach workspaces not on screen, workspaces a reload adds, and handed-over workspaces; a reload keeps row heights
- [x] `Layout` protocol rework: `LayoutInput` (count and parameters; the strip adds sizes and the view) and `LayoutGaps` (REFACTORING 11.3). Gaps are no longer stored in each workspace
- [x] TylerCore: `WindowSize`, per-window sizes in `Workspace` (carried by `WorkspaceRow.move`, forgotten when a window leaves), `StripLayout` and `StripColumns` (packing, fit, end clamp, snap points), `LayoutInput.sizes` and `firstVisible`. Not a `LayoutKind` yet
- [x] TylerCore: the view (`Workspace.firstVisible`, refitted after every change so the focused window stays in view; `scroll(toFirstVisible:)` moves focus into the view), `arrangement`/`placements`/`offView`/`restingPlacements` (a frame is in view when its centre is), sizes and view in `SavedState` (optional fields)
- [x] TylerServer: `LayoutKind.strip` (`↔` in the menu bar), off-view windows parked by `applyLayout` and kept on their workspace by the sync, only windows in view slide between workspaces, `tiling off` brings off-view windows back, focusing a window out of view (command or click) scrolls to it
- [x] `tyler size half|full|quarter|next` (kept in every layout, used by the strip; a window forgets it when it leaves tiling, keeps it on another workspace)
- [x] `size quarter` stacks the focused window with the next one (or the previous one if the next already shares a column); leaving a pair (another size, closing, floating, moving away) puts the mate back to `half`. Changed 2026-10-11 after the user tried it on real windows: setting each window to `quarter` separately felt clumsy
- [x] Animated scroll: `ScrollPlan` (TylerCore) from the arrangements before and after; windows out of view at both ends stay parked, incoming ones start where they are parked, x kept inside `Parking.allowedX`. Used by `focus`, `swap`, `size` and a click on a window out of view; the focus event a scroll causes lets it run on
- [x] Swipe scrolls the strip (`PanTarget.strip`, `StripScroll`): the views it can rest at are worked out when the pan begins, and the windows follow the fingers along the scroll between the two views the position lies between. On release `Snap` picks a view (a flick goes on), focus moves into the view if it left it. On a strip workspace the swipe never switches workspaces, even when the strip fits. No rubber band at the ends yet: the content just stops
- [x] Manual: the `strip` layout under Layout, `layout strip`, `size`
- [x] Tried on real windows by the user (2026-10-11): switching to the strip, scrolling by focus, swiping (smooth), `size quarter`
- [ ] Checked against real windows: windows leaving on the left stop beside a left Dock, then park; a slow app (Firefox) during a scroll and a swipe; `tyler restart` keeps the view; `quarter` windows against apps' minimum heights; a click on a parked window's sliver
- [ ] Open: quarters feel odd to the user even with pairing. Pairs follow from list order, not real columns, so `swap` can split a pair (each half then shows like `half`). Rethink, maybe as explicit columns or a stack command
- [ ] Open: mouse resizing in the strip (an edge drag snaps back now); swap by drag only between windows in view
- [ ] Open: no rubber band at the strip's ends (the content just stops)
- [ ] Open: on a strip workspace the swipe never switches workspaces (decided with the user), so leaving one takes a key

### Workspace map in the menu bar (added 2026-10-11, between milestones)
Plan: `plans/workspace-map-indicator.md` (planned with the user 2026-10-11). A second menu bar item next to the text one: one small thumbnail per workspace, a rectangle for each tiled window placed as its layout places it, an outline around the current workspace and a blue (accent-coloured) border on the focused window. A left click on a thumbnail switches to that workspace; a right click opens the same menu as the text item. `[indicator] text|map` switch each item on or off. First, as a refactoring with no change in behaviour, every indicator moves into a new `TylerIndicators` target. Behind a common interface (`IndicatorSnapshot` and the `Indicator` protocol in TylerCore), the server only hands over a snapshot.

Decisions while building: the layouts already split whole-point areas in whole points, so the map doesn't round (a test guards it). The current workspace's outline sits just outside its thumbnail, in a 2-point margin around the map, so it doesn't merge with the faint slot. The focused window's border is drawn inside its rectangle. After trying it, the user found the 14-point thumbnails too small (2026-10-11): they now fill the status item's height (`NSStatusBar.system.thickness`, 22 points, less a 2-point margin, so 18), and the row may be 260 points wide before the thumbnails get lower. Then, to use all 22 points (the button's height: the rest of the notch Mac's 39-point menu bar can't be drawn in), the outline went (decided with the user, 2026-10-11): the current workspace's windows are bright and the others' dimmed (`secondaryLabelColor`), and its slot is a little brighter (`tertiaryLabelColor` against `quaternaryLabelColor`), which marks it when empty. This replaces the earlier decision that windows are equally bright everywhere. The focused window is filled light blue (the accent colour blended 40% with white) instead of bordered (the user, 2026-10-11).

- [x] `TylerIndicators` target; the text item moved there with no change in behaviour
- [x] `WorkspaceMap` model (thumbnails, windows by their layouts, focus, hit-testing), unit tested
- [x] `MapIndicator` and `IndicatorGroup`; tylerd shows both items
- [x] `[indicator] text|map`, parsed and unit tested; `reload` hands the settings to the items
- [x] Checked on screen (2026-10-11, macOS 26.7, by Claude): the text item is unchanged (`live-check menubar`), and the map item sits left of it (122×24 for four workspaces)
- [ ] The map matches `tyler list` for tall with 1, 2 and 3 windows, for full, and for strip
- [ ] The outline follows `workspace next`; the focus border follows `focus next`
- [ ] `ratio +0.05` and a mouse resize update the map
- [x] A left click on each thumbnail switches to it, and one in a gap goes to the nearest; a right click and a ctrl-click on the map open the shared menu (read under the map item through Accessibility); the text item's menu still opens (2026-10-11, by Claude, with synthetic clicks; the hit-testing matched the thumbnails exactly)
- [ ] The menu opened from the map sits under the item like the text item's (needs the user's eyes)
- [ ] Light and dark menu bars both look right
- [x] `[indicator] text = false` and `map = false` with `reload` hide each item, and `true` brings it back (2026-10-11, by Claude)
- [ ] `tiling off` hides the map
- [ ] 10 workspaces fit

Notes from the live check (2026-10-11): synthetic clicks on a status item only arrive after a mouse move onto it; a click posted with `maskControl` leaves later synthetic events with control held, unless a control key-up is posted; and a synthetic Escape doesn't close a status item menu, so the next click only closes it (the same with the text item's menu). Screen capture needs Screen Recording permission, which the terminal doesn't have, so what the map looks like needs the user's eyes.

### M5. Multi-display
Per-display stacks keyed by display UUID, reconfiguration handling, `display` and `move-to-display`.

### M6. Config and service
Config file (float rules, gaps, workspace count), `reload`, LaunchAgent through `service install`.

Decisions (2026-10-10): the file is `~/.config/tyler/tyler.toml` (`TYLER_CONFIG` overrides it) and is optional. TOML is parsed by a small built-in parser (`TOML.swift`, no dependency) that supports tables, bare/quoted/dotted keys, single-line strings, integers, floats, booleans and comments, and rejects arrays, inline tables, multi-line strings and dates with an error; extend it when float rules need arrays of tables. Unknown keys are errors. Gaps are `[gaps] inner/outer`, whole points ≥ 0, the same on every workspace (`[mouse] follow-interval` joined later, see Mouse resizing); reload keeps each workspace's layout and ratio. A broken file at startup prints the error and starts with the defaults; a broken file on `reload` returns an error (exit 1) and keeps the current settings; a missing file means the defaults. `reload` works with tiling off or before permission (it only stores the config) and re-tiles only the current workspace.

- [x] TylerCore: `TOML`, `Config` (`gaps`), `ConfigError`, `ConfigSource` (file reader, injectable for tests), `Paths.configPath`, `LayoutParameters.withGaps`, `Workspace.setGaps`, `WorkspaceStack.setGaps` (all replaced by `LayoutGaps` in the strip layout's rework), `Request.reload`
- [x] TylerServer: `WindowManager` takes a `Config` and a `ConfigSource`; `reload` in `WindowManager+Config.swift`
- [x] tylerd loads the config at startup; TylerClient: `reload`
- [x] Checked against real windows (2026-10-10, by Claude): gaps at startup (`outer = 12`, `inner = 8` measured in `list`), `reload` after editing the file (`inner = 30` gives a 30-point gap and keeps stack heights), a broken file on reload (exit 1, the error names the key, nothing moves)
- [ ] A broken file at startup
- [x] `tyler start|stop|restart|status` (decided 2026-10-10): `start` spawns the `tylerd` next to `tyler` (symlinks resolved) with `posix_spawn` in a new session, stdin from /dev/null, output in `~/.tyler/tyler.log` (socket path with `.log`; truncated on start), no inherited fds, and waits up to 10 s for `status` to answer. `stop` sends SIGTERM to the pid from `status` and waits up to 10 s. A detached child keeps the terminal as the process responsible for Accessibility, so rebuilds need no new grant; a LaunchAgent would need its own grant and a stable signature (see Code signing), so `service install` will move these commands onto launchd later. `status` reports pid, binary, config, tiling, uptime, and warns when the binary's modification time is newer than at launch. The server answers JSON it can't decode with `unknown request: tylerd is probably older than tyler (run tyler restart)`. A server from before `status` existed can't be stopped by `tyler stop` (it doesn't report its pid); `tyler` says to use `pkill tylerd` once.
- [x] **Restart keeps the windows in place** (decided with the user 2026-10-10; plan: `plans/restart-keeps-windows.md`): `tyler restart` sends SIGUSR1, tylerd writes its workspaces to `~/.tyler/tyler.state.json` (`SavedState`) and exits without moving a window, and the next tylerd carries on from the file and deletes it once windows are tracked. Windows are matched by `CGWindowID`. `stop`/SIGTERM still restore. `ServerStatus.keepsWindowsOnRestart` (nil for older servers) makes restart fall back to SIGTERM against a tylerd that would die on SIGUSR1.
- [x] Checked for real (2026-10-10, 7 windows on workspaces 1–3, workspace 3 in `full`): a restart keeps every window on its workspace and in its slot, and moves nothing (`tyler list` and the menu bar identical before and after; the state file is removed). The first restart from the older tylerd fell back to SIGTERM and said so. Each workspace's layout after the restart is covered by unit tests only.
- [x] Checked for real (2026-10-10, by Claude): `status` warns once the binary is newer; `restart` then starts a new tylerd that has Accessibility, and `list` and the menu bar are byte-identical before and after
- [ ] Checked for real: `tyler start` survives closing the terminal; `stop` restores windows
- [x] Workspace count (2026-10-10; plan: `plans/workspace-count-and-app-rules.md`): `[workspaces] count`, 1 to 10, default 4. `reload` applies it at once: new workspaces are added empty at the bottom; removed ones merge their windows into the new last workspace (appended in order), which becomes current if the current one was removed, then the current workspace re-tiles without a slide. A restart with a smaller count merges the handed-over workspaces the same way. Unit tested only
- [ ] Checked against real windows: growing and shrinking the count with `reload`
- [x] App assignments (2026-10-10, same plan): `[assign]` maps an app name or bundle ID (case-insensitive; the bundle ID wins) to a workspace number within `workspaces.count`. The rule applies once, to a window that has never been tiled (`WindowManager.seen`, carried in `SavedState.seen`; older state files count every window they list): at startup, when it opens, or when it first becomes tileable. A window assigned to a parked workspace is parked there directly, no slide. If it has focus (the usual case for a new window, whichever of `created` and `focused` arrives first), its workspace comes into view, so keys never go to a parked window. `reload` applies new rules to new windows only. Unit tested only
- [ ] Checked against real windows: a new Firefox window (app already running, and a cold launch) lands on its workspace and the view follows; a window opened in the background (e.g. `open -g`) stays parked; startup with Firefox frontmost
- [ ] Float rules
- [ ] LaunchAgent (`service install|uninstall`)

### M7. (Later) Trackpad scroll and swipes
Scroll with a modifier through a CGEventTap feeding the Animator. Trackpad swipe gestures switch workspaces, for example a three-finger swipe left/right for the previous/next workspace (macOS uses three- and four-finger swipes for Spaces by default, so this needs checking). Both arrive through `PointerInput`.

Swipes (plan: `plans/trackpad-swipe.md`, decided with the user 2026-10-10): built into tylerd, interactive (windows follow the fingers, then snap to the neighbouring workspace or back), with a 3-finger horizontal swipe. The code is layered as pan (touches to an offset), snap (pick a settle point) and scrollable (what moves: the workspace row now, the strip layout later).

- **Measured 2026-10-11 (macOS 26.7, `devtools/live-check gestures`):** a listen-only `CGEventTap` (session tap) for gesture events (`NSEvent.EventType.gesture`, 29) gets every touch frame, with `NSEvent(cgEvent:).allTouches()` giving finger count and normalized positions. That holds even with 3- and 4-finger horizontal swipes assigned to Spaces in System Settings. A 3-finger swipe gave 30–54 frames (about 100 per second while moving) and about 0.2 trackpad widths of horizontal travel; a 4-finger swipe looked the same. `NSEvent.addGlobalMonitorForEvents(matching: .gesture)` got nothing, so the tap is the source. The terminal's existing grants were enough (no new permission prompt). Touches come and go one finger at a time, so a 3-finger contact is framed by 1- and 2-finger frames, and short 3-finger blips (1–4 frames) happen as fingers land and lift.
- [x] TylerCore: `TouchFrame`, `PanUpdate`, `PanRecognizer` (finger count, sideways lock after 0.03 trackpad widths, vertical contacts ignored until the fingers lift, release velocity over the last 50 ms)
- [x] TylerCore: `Snap` (nearest point, a flick goes on to the next one, resistance past the ends), `Easing.linear` and `easeOut`, `Track.position(at:easing:)`; TylerServer: `Animator.run(_:from:to:move:)` finishes a slide from part-way, easing out, in the duration's share of the distance left
- [x] Config `[gestures]`: `swipe` (default true), `fingers` (3 or 4, default 3), `swipe-distance` (trackpad widths for a whole workspace, 0.1 to 1.0, default 0.3: the measured swipes travelled about 0.2). Not in the manual until the swipe works
- [x] TylerServer: `PointerEvent.pan`, `WindowManager+Pan`. A pan works out both neighbours' slides when it begins (`SlidePlan`, shared with `show`), and the windows follow the fingers linearly, placed at most once a frame (newer offsets replace older ones, like the drag following). On release `Snap` picks the neighbour or the way back (a flick of 1 display width per second goes on), and the Animator finishes from where the fingers left off, easing out. Turning back past the start swaps the neighbour. A command, reload or focus change mid-pan puts the windows back. Off with `gestures.swipe = false`, with one workspace, with tiling off, or during a mouse drag. The pan's target is an enum (`PanTarget.workspaceRow`) rather than the planned `Scrollable` protocol, which would have one implementation; the strip layout adds a case
- [x] TylerPlatform: `SwipeTap` (the listen-only gesture tap, feeding a `PanRecognizer`; turns itself back on if macOS disables it), owned by `PointerMonitor`. `PointerInput.watchSwipes(fingers:)` is set from the config at start and on `reload` (`nil` when `gestures.swipe` is off)
- [x] Checked against real windows by the user (2026-10-11): full swipes worked at once. Slow swipes first started late, with a jump, and flickered, and going back from a short swipe was too fast. Fixed by counting the offset from where the pan begins (lock distance 0.015), a `OneEuroFilter` on the offset (2 Hz when still, rising 20 Hz per trackpad width per second), and going back taking at least 60% of a slide. After that: "awesome"
- [ ] Checked against real windows: swiping right from workspace 1 wraps to the last; 4-finger and vertical swipes do nothing; a swipe with Firefox on screen keeps up
- [x] Manual: "Swiping between workspaces" and the `[gestures]` settings
- [ ] Open: whether macOS also acts on a 3-finger swipe left assigned to Spaces when there is a Space or full-screen app to switch to (the user has none). The manual tells users to move that gesture to 4 fingers.

## CLI target (v1)
```
tyler start | stop | restart | status
tyler ping | list [--json] | reload | retile
tyler focus next|prev|master            tyler swap next|prev|master
tyler layout tall|full|next             tyler ratio +0.05|-0.05
tyler float toggle
tyler workspace prev|next|<n>           tyler move-to-workspace prev|next|<n> [--follow]
tyler display next|prev                 tyler move-to-display next|prev
tyler service install|uninstall
```
What is implemented is the command table in `TylerClient/CommandLine.swift` (`tyler` without arguments prints it); `docs/manual.md` describes each command, and a test keeps the two in step. The CLI and wire format say `master` (the xmonad term); in Swift the case is `ListTarget.main`, because SwiftLint's `inclusive_language` rule rejects `master` in identifiers.

## Open items
- **Code signing.** No signing identity exists on this machine. macOS ties the Accessibility permission to the binary's code identity. Decided in M2: during development, grant Accessibility to the terminal app that runs `tylerd` (no keychain changes). Revisit in M6, when `tylerd` runs as a LaunchAgent and needs its own stable identity (a self-signed `tyler-dev` certificate, then `make install SIGN_ID=tyler-dev`).
- **The `Layout` protocol only gets a window count** (and the area and parameters). Being reworked for the strip layout: `LayoutInput` carries per-window sizes and the view anchor, gaps move to `LayoutGaps`, and off-view frames are parked rather than placed (see Strip layout).
- Native fullscreen windows are left alone. Terminals that snap to character cells won't fill their frame exactly.
- AX calls cost one round trip per window, so a slide with many windows may be coarse (see M4). Each slide frame runs on the main thread, and an unresponsive app can block a frame for up to the 1 s AX timeout.
- **Crash recovery (from M4).** A crash or `kill -9` skips `stop()`, so parked windows stay at the right edge. A state file of original frames, read at the next start, would fix it; out of scope for M4.
- **Parking with several displays (M5).** Windows park at the primary display's right edge. With a display to its right, a parked window shows on that display, and macOS may not accept the position. M5 needs to pick an edge that touches no other display (the left edge works too, but with the Dock there it leaves a strip visible), and the slide direction may have to follow it.
- **Focus after closing a window (from M4).** When a window closes, macOS may focus another window of the same app, even one parked on another workspace, and tylerd then switches there. Unverified; if it happens, ignore focus events for parked windows right after a window of the same app closes.
- **Focus after switching to an empty workspace** stays on the previous workspace's (now parked) window, so typing goes to a hidden window. **Confirmed 2026-10-10:** after `workspace 4` (empty), `list` still flagged the parked window of the previous workspace as focused. **Fixed the same day:** when the current workspace ends up empty (a switch, or `move-to-workspace` of its last window) and a parked window has focus, tylerd makes itself frontmost through AX (`WindowBackend.unfocus`). A focused floated window keeps focus. Checked on real windows: on the empty workspace the frontmost app is `tylerd`, and switching back focuses the workspace's window again.
- **Echo tracking can go stale.** If an app accepts a focus call but never sends a focus event, the window stays on tylerd's "own focus" list, and the next real focus of it while parked doesn't switch workspaces (once). Unverified whether this happens.

- **Testing pitfalls found in M1.** (1) Tests that block in `read()` must not run on Swift concurrency's cooperative pool: a task-group version of the concurrent-clients test failed ~80% of runs, plain threads pass. The cause is suspected, not verified. (2) A test that writes more than the socket buffer (~8 KB) on the same thread that later reads will deadlock. (3) macOS has no `timeout`; use `perl -e 'alarm N; exec @ARGV' cmd` to bound a run.

- **GCD (settled in M2).** Kept at the edges as a documented exception in `devdocs/coding-guidelines.md`: `IPCServer` (blocking socket I/O) and `tylerd`'s signal sources. Everything else is `@MainActor` / async.
- **`IPCServer.runBlocking` needs a free main thread.** Each socket worker blocks on a semaphore while the main actor answers. That works under `NSApplication.run()`, but anything that blocks the main thread (a long AX call) also stalls every `tyler` command. AX calls have a 1 s messaging timeout for that reason.
- **Only standard apps are observed** (`activationPolicy == .regular`), and windows on other Spaces are invisible to AX. Menu-bar-only apps and other Spaces are not tracked.
- **`AXBackend` retries** attaching to a new app up to 6 times at 500 ms, then gives up (logged through `Logger`, subsystem `tyler`). The numbers are guesses until checked against real apps.

## Log
- 2026-10-08: M1 built.
- 2026-10-08: M2 built and unit tested. The user then ran it against real windows and reported it works well (see M2 for what was and wasn't confirmed).
- 2026-10-10: M4 built and unit tested (all three phases of the plan). Not yet run against real windows (see M4 for the checklist).
- 2026-10-10: `tyler start|stop|restart|status` built and unit tested; spawning checked with a stub `tylerd` (detached, log captured, early exit and timeout reported), not yet with the real server.
- 2026-10-10: M6 started: config file (`tyler.toml`) with gaps, and `tyler reload`. Unit tested, not yet run against real windows.
- 2026-10-10: `tyler restart` keeps the windows in place (hand-over through a state file), in four commits following `plans/restart-keeps-windows.md`.
- 2026-10-10: Renamed the project from mwm to tyler: binaries `tyler`/`tylerd`, modules `Tyler*`, socket `~/.tyler/tyler.sock`, `TYLER_SOCKET`, Logger subsystem `tyler`. The repository directory is still `mwm`.
- 2026-10-10: Renamed "virtual monitor" to "workspace" everywhere (see Decisions) and wrote the Concepts section of `docs/manual.md`.
- 2026-10-10: Mouse resizing built and unit tested (`plans/mouse-resize.md`); not yet run against real windows.
- 2026-10-10: Swap by drag and drop built, unit tested and checked against real windows by the user (`plans/swap-by-drag.md`). Resizing the dragged window to the target slot during the preview was tried and dropped (see Swap by drag and drop).
- 2026-10-10: First verification pass against real windows by Claude (macOS 26.7, 8 windows on 3 workspaces): workspace switching, `move-to-workspace`, layouts, ratio, swap, focus, reload, stale warning and restart behave; switching to an empty workspace leaves focus on a parked window.
- 2026-10-08: M3 built and unit tested. The code that moves and focuses windows has not been run against real windows (see M3 for the checklist). Not recoverable on exit yet: quitting `tylerd` leaves windows where tiling put them (M4 adds restore).
- 2026-10-11: Strip layout built and unit tested on the `strip-layout` branch (`plans/strip-layout.md`), tried on real windows by the user, and merged into `main`. Open items in its section.
