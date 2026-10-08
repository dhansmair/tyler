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

**Not verified (needs Accessibility permission, which this session doesn't have):**
- [ ] The whole MWMPlatform layer has never run against real windows. The planned spike (confirm AX events arrive under `NSApplication.run()`, check what `kAXWindowsAttribute` returns) was skipped and the layer was written straight from the AX documentation.
- [ ] Manual checklist, with Accessibility granted to the terminal that runs `mwmd`: `mwm list` shows your windows; open, close, move, resize, minimize and focus TextEdit/Terminal windows and re-run `list` after each; quit an app with several windows; open a Save panel and check it shows `dialog`; check a fullscreen window shows `full`; check frames are in top-left coordinates and `DISPLAY` is right.
- [ ] Confirm `dispatchMain()` was really insufficient and `NSApplication.run()` is needed (not tested, I assumed it).

### M3. Tiling on one display
Workspace list operations, `Layout` protocol, `tall` and `full`, focus/swap/layout/ratio/float. The biggest batch of unit tests.

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
Implemented so far: `ping`, `list [--json]`.

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
- 2026-10-08: M2 built and unit tested; the AX layer is unverified against real windows (see M2).
