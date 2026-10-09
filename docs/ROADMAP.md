# mwm roadmap (working document)

Update this file as work progresses: tick off items, log decisions, and move open questions into the decisions log once they're settled. It's the source of truth between sessions.

## Goal
A personal macOS window manager in Swift, replacing AeroSpace/Amethyst for this workflow:
- **xmonad-style tiling.** Each workspace is an ordered list of windows with a clear prev/next and a master (the first window). Typical use is two windows side by side, sometimes one on the left and two stacked on the right. Layouts must be extensible.
- **Virtual monitors stacked vertically**, like pages. Scroll up and down between them with a snap.
- **Server plus CLI.** `mwmd` runs in the background, and `mwm` sends it commands.

## Decisions
- Scrolling between virtual monitors is CLI-driven in v1 (animated slide and snap). Trackpad scrolling with a modifier key comes later.
- New windows tile by default. Dialogs, sheets and apps listed in the config float. `float toggle` switches any window.
- Multiple physical displays, with **one vertical stack of virtual monitors per display**. Commands act on the focused display.
- Hotkeys are external (skhd, Karabiner, Raycast). mwmd has no hotkey code.
- Every component is unit tested with Swift Testing (`import Testing`). It ships with the Command Line Tools, and XCTest isn't available.
- The executables stay thin. Logic lives in libraries, and everything that touches macOS (AX, NSScreen, timers) sits behind a protocol so tests can use fakes.
- IPC: one newline-delimited JSON request and one response per connection over a Unix socket (`~/.mwm/mwm.sock`, override with `MWM_SOCKET`).
- Virtual monitors work by parking windows of inactive monitors in a display corner with about 1px visible (the AeroSpace trick).

## Package layout
```
Sources/
  MWMCore/     pure value types and POSIX helpers: Protocol, Paths, UnixSocket, Window, Display, (later) Layout, Workspace, DisplayStack, Config, Parking, Animation
  MWMServer/   server logic behind protocols: CommandRouter, IPCServer, WindowManager, WindowRegistry, Backend protocols, (later) Animator
  MWMPlatform/ real macOS implementations, not unit tested: AXBridge, AppObserver, AXBackend, system providers, (later) display link
  MWMClient/   argv parsing, response formatting, socket client
  mwmd/        server executable (thin)
  mwm/         CLI executable (thin)
Tests/         one test target per library
```

## Milestones

### M1. Skeleton, IPC and test harness
- [x] docs/ROADMAP.md
- [x] Package with MWMCore, MWMServer, MWMClient, `mwmd`, `mwm`
- [x] `Request`/`Response` protocol and `Paths`
- [x] Unix socket helpers and `IPCServer` (stale-socket handling, single-instance check)
- [x] `mwm ping` → `pong`, usage errors, "mwmd is not running" error
- [x] Tests for protocol, sockets, router, IPC round trip, CLI parsing and output
- [x] Makefile (`build`, `test`, `install`). `make test` is needed instead of plain `swift test`: the Command Line Tools ship Swift Testing, but SwiftPM doesn't find it without extra framework/rpath flags, which the Makefile passes.
- [x] Verified: 28 tests pass (`make test`, about 3 s), and `mwm`/`mwmd` checked by hand (ping, no server, duplicate server, SIGTERM removes the socket)
- [x] `swift format lint --strict` and `swiftlint --strict` are clean, and a pre-commit hook (`.pre-commit-config.yaml`) runs both plus `make test` on every commit that touches Swift files. SwiftLint needs `TOOLCHAIN_DIR=/Library/Developer/CommandLineTools` when full Xcode isn't installed; `.swiftlint.yml` aligns it with swift-format.
- [ ] Stable code signing for Accessibility (**deferred to M2**, see open items)

### M2. AX spike and window discovery
`mwmd` keeps a live list of the standard windows on the current Space, and `mwm list [--json]` shows it. It does not move, resize, focus or raise anything (that's M3).

Built and tested:
- [x] MWMCore: `WindowID`, `WindowInfo`, `WindowKind.classify`, `DisplayInfo`, `DisplayGeometry` (AppKit→AX y-flip, window→display by overlap), `Request.list` / `Response.windows`
- [x] MWMServer: `WindowRegistry` (idempotent events), `WindowManager` (`@MainActor`), `WindowBackend` / `DisplayProvider` / `AccessibilityGate` protocols, async `CommandRouter`, async `IPCServer.Handler` with one blocking-to-async bridge
- [x] MWMClient: `mwm list [--json]`, text table and JSON output
- [x] MWMPlatform (new): `AXBridge`, `AppObserver`, `AXBackend`, `SystemAccessibilityGate`, `ScreenDisplayProvider`
- [x] `mwmd` runs a real `NSApplication` run loop (`.accessory`), polls for the permission and starts tracking once it is granted
- [x] 81 tests pass; `swift format lint --strict` and `swiftlint --strict` are clean
- [x] Verified by hand without permission: `ping` works, `list` and `list --json` exit 1 with the instructions, bad usage exits 2, SIGTERM stops `mwmd` and removes the socket

**Manually verified by the user (2026-10-08):** with Accessibility granted, `mwmd` and `mwm list` work well against real windows. The checklist below records which items were confirmed.

**Not verified by Claude (this session has no Accessibility permission):**
- [ ] The whole MWMPlatform layer had never run against real windows when it was written (the user has since run it, see above). The planned spike (confirm AX events arrive under `NSApplication.run()`, check what `kAXWindowsAttribute` returns) was skipped and the layer was written straight from the AX documentation.
- Manual checklist, with Accessibility granted to the terminal that runs `mwmd`. Confirmed by the user so far:
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
`mwmd` keeps an ordered list of tiled windows (xmonad style: the first is the main window, everything has a next and a prev), lays it out with `tall` or `full`, and is driven by CLI commands. This is the first milestone where `mwmd` moves your windows.

Decisions: tiling starts when `mwmd` has permission (kill switch: `mwm tiling off`); dragging or resizing a window by hand is left alone until the next re-tile (tiling reacts only to commands and to windows appearing, disappearing, or becoming un/tileable); one workspace on the primary display's visible frame; new windows go after the focused one; windows present at start are ordered left to right.

Built and unit tested:
- [x] MWMCore: `Layout` protocol, `LayoutParameters` (ratio clamped to 0.1…0.9, outer/inner gap), `TallLayout`, `FullLayout`, `LayoutKind`, `Workspace` (insert/remove/sync, focus and swap with wrap-around, ratio, layout cycle), command types, `slot` and `isFloated` on `WindowInfo`
- [x] MWMServer: `WindowBackend.setFrame` / `focus`, tiling in `WindowManager` (reconcile on events, skips windows already in place, one failing window never stops the others), router forwards every command
- [x] MWMClient: `focus`, `swap`, `layout`, `ratio`, `float toggle`, `tiling`, `retile`; `SLOT` column and `floated` flag in `list`
- [x] MWMPlatform: `AXBridge.setFrame` (size, position, size) and `raise`, `AXBackend.setFrame` / `focus`
- [x] 195 tests pass; `swift format lint --strict` and `swiftlint --strict` are clean
- [x] Verified by hand without permission: every new command exits 1 with the permission instructions (`tiling off` works), bad arguments exit 2 with the valid choices, SIGTERM stops `mwmd` and removes the socket

**Not verified (needs Accessibility permission, which Claude's session doesn't have):** the code that actually moves and focuses windows (`AXBridge.setFrame` / `raise`, `AXBackend.setFrame` / `focus`) has never run against a real window. Checklist for the user. Run `mwm tiling off` from a second terminal if anything goes wrong:
- [x] (2026-10-10, run by Claude with Accessibility granted) Windows at start tile: one left, the rest stacked on the right (5 windows seen)
- [x] `focus next|master` moves focus across apps (Ghostty to Code and back); the `focused` flag follows. `prev` and the actual keyboard/raise were not checked separately
- [x] `swap next|master`, `layout tall|full`, `ratio +0.05|-0.05`, `float toggle` (twice), `retile`, `tiling off` then `on` all behave. Not run: `swap prev`, `layout next`. Note: toggling float back on re-inserts the window after the focused one, so the old master lost its slot
- [ ] Closing, minimizing and fullscreening a tiled window re-tiles the rest; dragging a window does not snap back until `mwm retile`
- [ ] The menu bar and the Dock side are respected
- [ ] A terminal (character-cell snapping) and a window with a minimum size (such as System Settings) end up where expected, and `list` shows their real frames
- [x] `list` shows sensible `SLOT` values and `floated`
- [ ] The size-position-size sequence in `AXBridge.setFrame` is actually needed (it is a common AX technique that I did not verify here)
- [ ] The frontmost-app plus raise approach in `AXBridge.raise` works for an accessory app like `mwmd` (I chose it because the SDK documents `NSRunningApplication.activate` as cooperative and not guaranteed)

### M4. Virtual monitors and the animation spike
DisplayStack, parking, Animator, `monitor` and `move-to-monitor`, restore on exit. Check early whether the slide feels good enough, and decide whether the snapshot-overlay fallback is needed.

### M5. Multi-display
Per-display stacks keyed by display UUID, reconfiguration handling, `display` and `move-to-display`.

### M6. Config and service
Config file (float rules, gaps, monitor count), `reload`, LaunchAgent through `service install`.

### M7. (Later) Trackpad scroll
Scroll with a modifier through a CGEventTap feeding the Animator.

## CLI target (v1)
```
mwm ping | list [--json] | reload | retile
mwm focus next|prev|master            mwm swap next|prev|master
mwm layout tall|full|next             mwm ratio +0.05|-0.05
mwm float toggle
mwm monitor up|down|<n>               mwm move-to-monitor up|down|<n> [--follow]
mwm display next|prev                 mwm move-to-display next|prev
mwm service install|uninstall
```
Implemented so far: `ping`, `list [--json]`, `focus`, `swap`, `layout`, `ratio`, `float toggle`, `tiling`, `retile`. The CLI and wire format say `master` (the xmonad term); in Swift the case is `ListTarget.main`, because SwiftLint's `inclusive_language` rule rejects `master` in identifiers.

## Open items
- **Code signing.** No signing identity exists on this machine. macOS ties the Accessibility permission to the binary's code identity. Decided in M2: during development, grant Accessibility to the terminal app that runs `mwmd` (no keychain changes). Revisit in M6, when `mwmd` runs as a LaunchAgent and needs its own stable identity (a self-signed `mwm-dev` certificate, then `make install SIGN_ID=mwm-dev`).
- Native fullscreen windows are left alone. Terminals that snap to character cells won't fill their frame exactly.
- AX calls cost one round trip per window, so a slide with many windows may be coarse (see M4).

- **Testing pitfalls found in M1.** (1) Tests that block in `read()` must not run on Swift concurrency's cooperative pool: a task-group version of the concurrent-clients test failed ~80% of runs, plain threads pass. The cause is suspected, not verified. (2) A test that writes more than the socket buffer (~8 KB) on the same thread that later reads will deadlock. (3) macOS has no `timeout`; use `perl -e 'alarm N; exec @ARGV' cmd` to bound a run.

- **GCD (settled in M2).** Kept at the edges as a documented exception in `docs/coding-guidelines.md`: `IPCServer` (blocking socket I/O) and `mwmd`'s signal sources. Everything else is `@MainActor` / async.
- **`IPCServer.runBlocking` needs a free main thread.** Each socket worker blocks on a semaphore while the main actor answers. That works under `NSApplication.run()`, but anything that blocks the main thread (a long AX call) also stalls every `mwm` command. AX calls have a 1 s messaging timeout for that reason.
- **Only standard apps are observed** (`activationPolicy == .regular`), and windows on other Spaces are invisible to AX. Menu-bar-only apps and other Spaces are not tracked.
- **`AXBackend` retries** attaching to a new app up to 6 times at 500 ms, then gives up (logged through `Logger`, subsystem `mwm`). The numbers are guesses until checked against real apps.

## Log
- 2026-10-08: M1 built.
- 2026-10-08: M2 built and unit tested. The user then ran it against real windows and reported it works well (see M2 for what was and wasn't confirmed).
- 2026-10-08: M3 built and unit tested. The code that moves and focuses windows has not been run against real windows (see M3 for the checklist). Not recoverable on exit yet: quitting `mwmd` leaves windows where tiling put them (M4 adds restore).
