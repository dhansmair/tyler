# M3: Tiling on one display

## Context
M1 (IPC) and M2 (window discovery) are done and committed (`c9257c4`, `82e0dff`). You've confirmed on real windows that `list` tracks `min`, `full`, `focused` and removal on close. M3 is the first milestone where `tylerd` **moves your windows**: it keeps an ordered list of tiled windows (xmonad-style, with a clear prev/next and a master), lays them out with `tall` or `full`, and lets you drive it from the CLI.

Decisions settled with the user:
- **Tile on start, with a kill switch.** When `tylerd` has permission it tiles existing windows immediately. `tyler tiling off|on|toggle` stops and resumes it; windows stay where they are when it's off.
- **Manual drags and resizes are left alone** until the next re-tile. Tiling reacts only to commands and to windows opening, closing, minimizing, un-minimizing or entering/leaving fullscreen. A move or resize event never triggers a re-tile, so there's no feedback loop between tylerd's own moves and the AX move notifications they cause.

Assumptions I'm making (say if any is wrong):
- **One workspace, on the primary display's `visibleFrame`** (menu bar and Dock excluded). Windows on other displays are not tiled in M3. Per-display stacks come in M5. This machine has one display, so a second display can't be tested yet.
- **New windows are inserted after the focused window** (appended if nothing is focused). Windows that exist at startup are ordered by position (x, then y) so the first tiling doesn't shuffle them arbitrarily.
- **Gaps:** the layout code supports an outer and inner gap, tested, with default 0. A config option arrives in M6.

Not in M3: virtual monitors, parking windows, animation, multi-display, config file, restoring windows on exit (M4), rules for which apps float (M6).

## Design
Same rule as before: pure logic in libraries with unit tests, macOS calls behind a protocol, executables thin.

**TylerCore (pure, unit tested)**
- `LayoutParameters` (`masterRatio` clamped to 0.1…0.9, `outerGap`, `innerGap`) and `protocol Layout { func frames(count: Int, in area: CGRect, parameters: LayoutParameters) -> [CGRect] }`.
- `TallLayout`: 0 windows → none; 1 → the whole area; 2 → side by side; 3+ → master on the left, the rest stacked on the right with equal heights. Frames are integers, with remainder pixels given to the first slots, so frames cover the area exactly, with no 1px gaps or overlaps. That's the "two windows side by side, sometimes one left and two stacked right" case from your notes.
- `FullLayout`: every slot gets the whole area.
- `LayoutKind` (`tall`, `full`; `Codable`, `next` cycles) maps to a `Layout`. Adding a layout later means one new type and one case.
- `Workspace` (value type): ordered `[WindowID]`, `focused`, `layout`, `masterRatio`. Operations: `insert(after focus)`, `remove` (focus moves to a neighbour), `focus(next/prev/master)` with wrap-around, `swap(next/prev/master)` (the focused window keeps focus and moves slot; swapping master when already master swaps with the next slot), `setFocus`, `adjustRatio`, `cycle/set layout`, and `sync(eligible:)`, which drops windows that are no longer eligible, keeps the order of the rest, and inserts new ones after the focus. It reports whether membership or order changed.
- Protocol: new `Request` cases `retile`, `tiling(TilingMode)`, `focus(ListTarget)`, `swap(ListTarget)`, `layout(LayoutChoice)`, `ratio(Double)` and `toggleFloat`, plus `Response.ok` and `Response.message(String)`. `ListTarget` is `next|prev|master`, `TilingMode` is `on|off|toggle`, `LayoutChoice` is `tall|full|next`.
- `WindowInfo` gets two server-filled fields (like `displayID`): `slot: Int?` (1-based position in the tiling list, so you can see master and order) and `isFloated: Bool`.

**TylerServer (behind protocols, unit tested with fakes)**
- `WindowBackend` gains two actions: `setFrame(_:of:)` and `focus(_:)`, both `throws(BackendError)` (`windowGone`, `refused(String)`).
- `WindowManager` gains: `tilingEnabled` (default true), `floated: Set<WindowID>`, and one `Workspace`. After every backend event it runs `reconcile()`: eligible = tileable, not floated, on the primary display. `Workspace.sync` runs, and **only if it reports a change** does the manager re-apply the layout. That's how move/resize events are ignored. Applying the layout skips windows whose known frame is already within 1pt of the target (AX calls cost one round trip per window), and a failure on one window is logged through `Logger` and counted, but never stops the others. Focus events from the OS (the user clicking a window) update `Workspace.focused` if the window is in the list.
- With tiling off, the workspace commands (`focus`, `swap`, `layout`, `ratio`, `float`, `retile`) answer an error, "tiling is off". `tiling` itself always works.
- `float toggle` acts on the focused window: tiled → floated (removed from the list, left where it is), floated → tiled again. A window that isn't otherwise tileable (dialog, minimized, fullscreen) answers an error.
- `CommandRouter` forwards the new requests. Responses: action commands answer `.ok`, `tiling` answers `.message("tiling on")`, and `retile` answers `.message` only if some windows couldn't be placed.

**TylerPlatform (real macOS code, not unit tested)**
- `AXBridge.setFrame`: set size, then position, then size again. This is a sequence commonly used by AX window managers because clamping at screen edges can change the size after a move; I haven't verified it on this machine, so it's a manual-test item. `AXBridge.raise`: `AXRaise` action plus setting the window's main/focused attributes.
- `AXBackend.setFrame` and `.focus` look up the element by `WindowID` (the map from M2), call the bridge, and also activate the owning app through `NSRunningApplication` (exact macOS 14 API to be confirmed against the SDK when implementing; the headers show `activate(from:options:)` and `activate(options:)`).

**TylerClient**
- New commands: `tyler focus next|prev|master`, `tyler swap next|prev|master`, `tyler layout tall|full|next`, `tyler ratio +0.05|-0.05`, `tyler float toggle`, `tyler tiling on|off|toggle`, `tyler retile`. Bad arguments are usage errors (exit 2) with a message naming the valid choices.
- `tyler list` gets a `SLOT` column (and `floated` in the flags), `--json` carries the new fields. Action commands print nothing on success; `.message` is printed.

## Known pitfalls
- **AX calls block the main thread.** Each `setFrame` is a synchronous call with a 1 s messaging timeout, and IPC requests wait on the main actor. A re-tile of many windows, or one hung app, can stall `tyler` commands for a moment. Acceptable for M3. M4's animation will need a different approach (batching or off-main-thread), which I'll plan then.
- **Apps resist.** Minimum sizes, and terminals that snap to character cells, won't fill their slot exactly. tylerd doesn't fight this: the registry keeps whatever frame the app ends up with. The related risk is some apps animating or lagging when resized through AX. I know of an undocumented `AXEnhancedUserInterface` attribute that's reported to cause this, but it isn't in the SDK headers, so I won't touch it unless manual testing shows a problem.
- **A hung or misbehaving app** can make `setFrame` fail every time; it's logged and skipped on each re-tile.
- **Not recoverable on exit yet.** If you quit `tylerd`, windows stay where tiling put them. Use `tyler tiling off` first if you want to try things safely; the real restore logic arrives with M4.
- Swift 6 strict concurrency, SwiftLint `--strict`, and the guidelines (no force-unwraps, no swallowed errors, no new GCD) still apply.

## Steps
1. TylerCore: `Layout`, `LayoutParameters`, `TallLayout`, `FullLayout`, `LayoutKind`, `Workspace`, with their tests.
2. Protocol and `WindowInfo` additions, with round-trip tests.
3. TylerServer: backend actions, `WindowManager` tiling logic, router, extended `FakeBackend` (records `setFrame` and `focus` calls), manager tests.
4. TylerClient: parser and formatter changes, tests. IPC round trip for one action command.
5. TylerPlatform: `AXBridge.setFrame`/`raise`, `AXBackend` actions.
6. Docs: `devdocs/ROADMAP.md` (tick M3, record verified and unverified), `CLAUDE.md`. The uncommitted M2 confirmation edits to both files are committed together with this milestone.
7. Commit through the pre-commit hook (format lint, SwiftLint, `make test`).

## Tests (Swift Testing, hand-written fakes)
| Component | What is checked |
|---|---|
| `TallLayout` / `FullLayout` | 0–5 windows, exact coverage with integer frames and no overlap (odd sizes too), ratio clamping, gaps (inside the area, no overlap, correct spacing), 3 windows = 1 left + 2 stacked right |
| `LayoutKind` | `next` cycles and wraps, name round trip |
| `Workspace` | focus next/prev wrap, 0 and 1 windows, no focus yet, focus master; swap next/prev wrap, swap master (including already master), focus stays on the moved window; insert after focus and append without focus; remove the focused, first, last and only window; `sync` keeps order, drops ineligible, inserts after focus, reports changes; ratio clamping |
| Protocol | Parameterized round trip of every new request/response, one line per message |
| `WindowManager` + fake backend | Tiles existing windows on start (ordered by position); new window re-tiles; close re-tiles; minimize and fullscreen leave the layout and come back; **move and resize events cause no `setFrame` calls**; unchanged frames are skipped; focus/swap/layout/ratio call `setFrame`/`focus` with the right ids and frames; float toggle removes and re-adds, errors for dialogs; tiling off blocks commands and leaves windows alone, tiling on re-tiles; windows on a second display are ignored; one failing `setFrame` doesn't stop the rest and is reported by `retile`; OS focus changes update the workspace |
| CLI | Every new command and argument form, usage errors for bad choices and missing arguments, `SLOT` column and `floated` flag in the table and JSON |
| IPC | One action command end to end over a temp socket with the fake backend |
| AX layer | Not unit tested; manual checklist below |

## Verification
- `make test`, `swift format lint`, `swiftlint` and the pre-commit hook pass.
- **Manual checklist (needs you, since this session has no Accessibility permission):** start with `tyler tiling off` ready in a second terminal. Open 2 windows and run `tylerd`: they split side by side. Open a third: one left, two stacked right. Run `focus next/prev/master`, `swap next/prev/master`, `layout full`/`tall`/`next`, `ratio +0.05`/`-0.05`, `float toggle` twice, `retile`, and `tiling off` then `on`. Close, minimize and fullscreen a tiled window and check the rest re-tile. Drag a window and check nothing snaps back until `tyler retile`. Check the Dock side and menu bar are respected, a terminal window (character-cell snapping) and a window with a minimum size (such as System Settings), and that `tyler list` shows sensible `SLOT` values.
- I'll report which of these I could and couldn't verify. The AX write path stays unverified until you've run the checklist.
