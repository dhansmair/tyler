# M4: virtual monitors, animation and restore on exit

## Context
M3 tiles one workspace on the primary display. M4 adds the stacked virtual monitors from the roadmap: `monitor up|down|<n>` scrolls between them with a slide, `move-to-monitor` sends the focused window to another, and quitting `mwmd` puts every window back. Today `WindowManager` holds a single `Workspace` (`WindowManager.swift:30`) and decides membership from where a window currently is (`eligibleWindows`, `:219`). That breaks once windows are parked in a corner, so each monitor has to own its windows explicitly. `mwmd` also leaves windows tiled on exit (`mwmd/main.swift:66`).

## Decisions (agreed with the user)
- Fixed number of monitors, constant default **4** (M6 makes it configurable). Primary display only; per-display stacks are M5.
- `monitor up|down` **wraps** at the ends. `<n>` is 1-based and rejects out-of-range values.
- **Animation is built in from the start** (no snap-first phase). A snap is an animation with zero steps.
- On normal exit (SIGINT/SIGTERM) every window is restored to the frame it had when `mwmd` first saw it. Crash/`kill -9` recovery (state file) is **out of scope**; log it in the roadmap's open items.

## Decisions I made (flag at review)
- New windows go to the **current** monitor. A window that becomes tileable again (un-minimize) is treated as new.
- Floated windows and dialogs belong to no monitor and stay visible on every monitor.
- Parking: bottom-right corner of the display frame with 1px visible (the AeroSpace trick from the roadmap). The slide moves the outgoing windows off one edge and the incoming ones in from the other.
- A command that arrives mid-animation cancels it and jumps to the final state first, then runs.
- A focus event for a parked window (cmd-tab to an app whose window is parked) switches to that window's monitor.
- `monitor` and `move-to-monitor` require tiling on (same `requireTiling` as the other commands). `tiling off` restores parked windows to their original frames and clears monitor assignments. Visible windows stay put, as in M3.
- After a switch, focus goes to the target monitor's focused window. An empty monitor gets no focus call.

## Phases
Each phase is a vertical slice with its tests and doc updates.

### Phase 1: restore on exit
- `WindowManager` records each window's first-seen frame (from `.created` and the start snapshot, before any `setFrame`). Drop it on `.destroyed`.
- `stop()` cancels any animation, then `setFrame`s every known window back to its original frame, ignoring per-window failures (log them), before `backend.stop()`.
- The existing signal handler already calls `manager.stop()`; update its comment (`main.swift:61`).
- Tests (`WindowManagerTests`/`TilingTests`, fake backend): tiled windows return to original frames on stop; windows opened later restore too; destroyed and failing windows don't block the rest.
- Docs: ROADMAP M3 "not recoverable on exit" note, CLAUDE.md warning about `mwmd` not restoring.

### Phase 2: monitors, parking and animation
- **MWMCore:** `MonitorStack` (array of `Workspace`, current index, wrapping `up`/`down`, `select(n)`, `monitor(of:)`, move a window between monitors) and a `Parking` helper (corner frame for a display). Per-monitor `sync` reuses `Workspace.sync` (`Workspace.swift:65`).
- **Wire/CLI:** `Request.monitor(MonitorTarget)` with `up|down|<n>`; `WindowInfo.monitor`; CLI parsing in `MWMClient/CommandLine.swift`; `MONITOR` column in `list`.
- **Backend:** add `setPosition(_:of:)` to `WindowBackend` (`WindowBackend.swift:31`), implemented with one AX call in `AXBridge`/`AXBackend`. Animation steps use it. The final step of every move uses the full `setFrame`.
- **Animator:** protocol in MWMServer with a real implementation that steps eased positions over a duration, taking an injected `Clock` so tests run without sleeping. `WindowManager` keeps a reference to the running animation `Task`.
- **WindowManager:**
  - Replace the single `workspace` with `MonitorStack`.
  - `eligibleWindows` becomes per-monitor (assigned windows that still exist and are tileable; unassigned ones join the current monitor).
  - Ignore `.updated` frame changes for windows that are mid-animation or parked, so the manager doesn't fight its own moves (`apply`, `:191`).
  - `monitor` handler: cancel any animation, animate outgoing windows to the park position and incoming windows to their layout slots, focus the target's focused window.
- Tests: `MonitorStack` (wrap, range, assignment), parking geometry, `WindowManager` with a fake backend and fake clock (switching parks and unparks the right windows, new windows land on the current monitor, mid-animation commands snap, `tiling off` unparks), CLI parsing and formatter.
- Docs: ROADMAP, CLAUDE.md status and CLI target list.

### Phase 3: `move-to-monitor` and focus-driven switching
- `Request.moveToMonitor(MonitorTarget, follow: Bool)`; CLI `move-to-monitor up|down|<n> [--follow]`.
- Moving the focused window parks it (or slides it off) unless `--follow` is set, in which case the view follows it.
- Focus events for parked windows switch monitors.
- Tests: moving to the same monitor, to an empty monitor, with and without `--follow`, focus-event switching, and parsing.
- Docs: ROADMAP checklist and CLI target.

## Critical files
- `Sources/MWMServer/WindowManager.swift` (monitor stack, per-monitor membership, restore, animation hooks)
- `Sources/MWMServer/WindowBackend.swift`, `Sources/MWMPlatform/AXBridge.swift`, `Sources/MWMPlatform/AXBackend.swift` (`setPosition`)
- `Sources/MWMCore/Workspace.swift` (reused unchanged), new `MonitorStack.swift`, `Parking.swift`
- `Sources/MWMCore/Commands.swift`, `Protocol.swift`, `Window.swift`, `Sources/MWMClient/CommandLine.swift`, `ResponseFormatter.swift`
- `Sources/mwmd/main.swift` (comment only), `Tests/MWMServerTests/Fakes.swift` (fake `setPosition`, fake clock)

## Verification
Automated, after each phase:
```bash
make build
make test
swift format lint --recursive --strict Sources Tests Package.swift
TOOLCHAIN_DIR=/Library/Developer/CommandLineTools swiftlint --strict
```
Manual, after Phase 2 and 3 (this session has Accessibility, so I can run most of it with `MWM_SOCKET=/tmp/mwm-m4.sock`, but the animation's feel is the user's call):
- [ ] Windows return to their original frames after SIGTERM, including parked ones
- [ ] `monitor down|up|<n>` slides windows and ends with the right set visible; `monitor down` on the last wraps to the first
- [ ] New windows open on the current monitor; `list` shows the `MONITOR` column
- [ ] Parked windows are really hidden (about 1px visible) and macOS doesn't pull them back on screen
- [ ] Slide smoothness with 3+ windows (the open question from the roadmap: is the snapshot-overlay fallback needed?)
- [ ] `move-to-monitor` with and without `--follow`; cmd-tab to a parked window switches monitor
- [ ] `tiling off` with parked windows leaves a usable screen

## Risks and open items to log in the roadmap
- AX per-window round trips may make the slide choppy; unmeasured until Phase 2 runs.
- macOS may clamp parked windows back on screen; unverified.
- Focus after switching to an empty monitor stays on a parked window's app; unverified.
- Crash/`kill -9` leaves windows parked until a state-file recovery exists (out of scope).
