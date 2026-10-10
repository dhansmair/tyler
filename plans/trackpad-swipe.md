# Trackpad swipe between workspaces (M7, swipe part)

## Context
Today `tyler workspace prev|next` is the only way to change workspaces, so it needs a key bound through skhd, Karabiner or Raycast. The user wants to cycle through workspaces with a trackpad gesture, the way macOS Spaces work. Decided with the user on 2026-10-10:
- **Detection is built into tylerd**, not an external tool such as BetterTouchTool. This matches M7 in the roadmap ("both arrive through `PointerInput`").
- **The swipe is interactive from the start.** Windows follow the fingers, and on release they snap to the next workspace or back to the current one.
- **The gesture is a 3-finger horizontal swipe.** The user moves the macOS "swipe between full-screen apps" gesture to 4 fingers, or turns it off, and turns off 3-finger "swipe between pages".

Workspaces sit side by side in a horizontal row, so a horizontal swipe maps straight onto the model. Direction follows the content: fingers moving left pull the next workspace in from the right, the same as `workspace next`. `prev` and `next` wrap, like `WorkspaceStack`. With one workspace, a swipe does nothing.

Status: in progress (started 2026-10-10).

## Increments (one commit each)

### 0a. Fix the stale "vertical stack" wording (docs only)
The workspaces moved to a horizontal row a while ago, but several places still describe a vertical stack. The user caught this mid-planning: CLAUDE.md had steered the gesture discussion the wrong way. Reword them all to "a row of workspaces side by side, like pages; you move left and right between them, and the view snaps to one":
- `CLAUDE.md:6`, `:11` (the Terms line)
- `devdocs/ROADMAP.md:8`, `:12`, `:14`, `:20`
- `docs/manual.md:20` ("stacked vertically … numbered from 1 at the top" becomes numbered from 1 on the left; drop the "can't be vertical" justification, or keep it as history)
- `Sources/TylerCore/WorkspaceStack.swift:3` (doc comment), and the `ScrollDirection` doc comment in `Sources/TylerCore/Animation.swift`

The type name `WorkspaceStack` can stay ("stack" as in an ordered collection). Renaming it isn't part of this work.

### 0b. Spike: what macOS 26 actually delivers
Add a probe to `devtools/` (next to `LiveCheck`) that installs a listen-only `CGEventTap` on the main run loop for gesture events (`NSEvent.EventType.gesture`, raw value 29) and logs `NSEvent(cgEvent:)?.allTouches()`: the number of fingers, normalized positions, phases and event rate. Also try `NSEvent.addGlobalMonitorForEvents(matching: .gesture)` for comparison.

The spike answers these questions:
- Do 3-finger touches arrive once the system gesture is moved to 4 fingers? Do they still arrive while the system gesture keeps 3?
- Which permission is needed: Accessibility, which tylerd already has, or Input Monitoring?
- Which source is more reliable, the tap or the global monitor?

Record the results in `devdocs/ROADMAP.md` under M7, in the same style as the `Parking` measurements. If neither source works, stop and come back to the user (the fallback is the private `MultitouchSupport` framework).

### Design for reuse: a pan, a snap and a scrollable
A niri-style strip layout comes later (ROADMAP "Strip layout"): one workspace is a long horizontal strip that scrolls left and right and snaps to columns. It must be able to reuse the 3-finger swipe. So the gesture code has no workspace knowledge, and it splits into three layers:
1. **Pan** (TylerCore): touches become a continuous horizontal offset plus a release velocity. It knows nothing about workspaces or windows.
2. **Snap** (TylerCore): a 1-D model. It takes the offset, the velocity and a list of snap points, and picks where to settle. Workspaces snap to −width, 0 and +width. Strip columns will snap to column edges.
3. **Scrollable** (TylerServer): whatever the pan moves. It turns an offset into window positions, gives its snap points and commits the chosen one. The workspace row is the first one; the strip is the second, later. `WindowManager` routes a pan to one scrollable.

Not decided yet: once the strip exists, both it and the workspace row scroll horizontally, so the same gesture is ambiguous. Options include the strip scrolling first and spilling over into the next workspace at its end, different finger counts, or the modifier-scroll from M7. Record this as an open item in the roadmap. The layering above works with any of them, because only the routing in step 3 changes.

### 1. TylerCore: `PanRecognizer` (pure, unit tested)
New file `Sources/TylerCore/Pan.swift`:
- `TouchFrame`: a timestamp and touches, each touch an identity and a normalized position. TylerPlatform converts from `NSTouch`, so TylerCore never imports AppKit.
- `PanUpdate` enum: `.began`, `.moved(offset: Double)` (signed cumulative horizontal travel in trackpad widths; positive means fingers moving right), `.ended(velocity: Double)` (trackpad widths per second, from the last ~50 ms), `.cancelled`.
- `PanRecognizer` struct, `mutating func feed(_ frame: TouchFrame) -> PanUpdate?`:
  - It reacts only to exactly `fingers` touches.
  - It starts once the horizontal travel passes a small threshold and dominates the vertical travel. A vertical-first gesture is ignored, which leaves the vertical axis free for later use.
  - A change in finger count ends the pan.
  - There is no clamping or commit logic here.
  - Built (2026-10-11): `feed` returns `[PanUpdate]`, so a frame can give `.began` and the first `.moved` together. There is no `.cancelled`: the recognizer never cancels, and the server cancels a pan on its own (a command mid-pan).
- Tests in `Tests/TylerCoreTests`, parameterized: offsets, velocity, a vertical gesture ignored, wrong finger count, a reversal through zero.

### 2. TylerCore: `Snap` and slides that start part-way
- `Snap.target(offset:velocity:points:) -> CGFloat`: the nearest snap point to the offset projected by the velocity (a flick goes one point further in its direction, never more than one). The offset follows the fingers with rubber-banding past the first and last point. Pure and parameterized-tested. The strip reuses it unchanged.
- `Track` (`Sources/TylerCore/Animation.swift`): add a linear position, so windows track the fingers 1:1 during the drag, and `Easing.easeOut` for the settle.
- `Animator.run` (`Sources/TylerServer/Animator.swift`) gets a variant that runs between two offsets with a given easing. The duration scales with the distance left, so a nearly finished swipe settles quickly. Tests use the injected clock.

Built ahead of step 3 (2026-10-11): the `[gestures]` config from step 4 (`swipe`, `fingers`, plus `swipe-distance`), because the server needs the distance.

### 3. TylerServer: the scrollable and the workspace row (`WindowManager+Pan.swift`)
- `PointerEvent` (`Sources/TylerServer/PointerInput.swift`) gets `case pan(PanUpdate)`, and `apply(_:)` in `WindowManager+Mouse.swift` routes it on.
- A small internal `Scrollable` protocol (it will have two implementations, so it's allowed):
  - `snapPoints` (in points)
  - `place(offset:)`: move the windows for that offset, linearly, through `nudge`
  - `settle(at:)`: animate to the chosen point and commit or restore
  - `cancel()`
  
  `WindowManager` keeps a `PanSession { scrollable, latestOffset, isApplying }` next to `animation`. It converts trackpad widths to points with a configurable factor (default: one full pass of `fullDistance` equals the visible width). Moves are coalesced: offsets that arrive while the AX calls run replace each other, like `followPendingFrame`, so slow apps such as Firefox don't pile up events.
- `WorkspaceRowScrollable`, the first implementation:
  - **began**: `finishAnimation()`, `endDrag()`, `syncWorkspaces()`. Its points are −width, 0 and +width (only 0 when there is one workspace). Build both neighbours' tracks lazily the first time the offset's sign picks a side, using a helper extracted from `show(_:direction:focusing:)` (`WindowManager+Workspaces.swift:80`) that returns `(start, tracks, outgoingFinals, incomingFinals)`. `show` and the pan share it, so the parking and `allowedX` rules stay in one place. If the offset crosses zero, the side it left goes back to parked.
  - **settle(at: ±width)**: `workspaces.select(neighbour)` (wrapping), ease-out into the finals, then `focusCurrentWorkspace()`.
  - **settle(at: 0) / cancel**: ease back. The current windows return to their slots and the neighbour's windows go back to `Parking.frame`.
- `animatingWindows` covers the pan's windows, so `WindowManager+Sync.swift:32` leaves them alone. Mouse-drag following, which already checks `animation == nil`, also checks the pan session. Any command, `reload` or focus change that arrives mid-pan cancels it first.
- Tests use the existing fake `PointerInput` and backend:
  - settling on a neighbour lands there with its windows tiled and the others parked
  - settling at 0 restores both sides
  - wrap-around
  - one workspace does nothing
  - crossing zero mid-pan
  - a command mid-pan
  - a pan while tiling is off is ignored

Built (2026-10-11), with one deviation: the pan's target is an enum, `PanTarget` with the single case `workspaceRow(prev:next:)`, instead of a `Scrollable` protocol. The guidelines allow a protocol only for two real implementations or a test seam, and the strip will be the second case. Both neighbours' slide plans are worked out when the pan begins, because frames read later would be mid-slide.

### 4. TylerPlatform and config
- `PointerMonitor` (`Sources/TylerPlatform/PointerMonitor.swift`) adds the gesture source chosen in the spike, on the main thread with `MainActor.assumeIsolated` like the existing monitor. It converts touches to `TouchFrame`, runs `PanRecognizer` and yields `.pan(...)`. Keep it thin.
- Config `[gestures]`: `swipe = true` and `fingers = 3` (3 or 4). Parse it in `Sources/TylerCore/Config.swift` and apply it on `reload` (`WindowManager+Config.swift`). Include config tests for bad values.
- Add the defaults to `~/.config/tyler/tyler.toml` (memory: sync personal tyler.toml).

### 5. Docs
- `docs/manual.md`: the gesture, the `[gestures]` keys, and the System Settings changes (Trackpad > More Gestures: swipe between full-screen apps → 4 fingers or off; swipe between pages → not 3 fingers).
- `devdocs/ROADMAP.md`: an M7 checklist with the decisions and the unchecked "against real windows" items, plus an open item on the strip layout: how a horizontal pan is shared between the strip and the workspace row, and that the strip will plug in as a second `Scrollable`.

## Verification
- `make test`, `swift format lint --recursive --strict Sources Tests Package.swift` and `TOOLCHAIN_DIR=/Library/Developer/CommandLineTools swiftlint --strict` (pre-commit runs all three).
- `make build && tyler restart`, then on real windows:
  - A slow 3-finger swipe left, half-way and back: the windows follow and return, and `tyler list` is unchanged.
  - A full swipe and a quick flick: the next workspace comes in and focus is on it.
  - Swipe right from workspace 1 wraps to the last workspace.
  - Swipes with 4 fingers and vertical swipes don't trigger.
  - A swipe with Firefox on screen (the slow AX case): check the frame rate feels acceptable.
- Use the `live-check` skill to replay the slide and check that parked windows really end up parked after a cancel.
