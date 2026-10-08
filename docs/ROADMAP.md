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
  MWMCore/     pure value types and POSIX helpers: Protocol, Paths, UnixSocket, (later) Layout, Workspace, DisplayStack, Config, Parking, Animation
  MWMServer/   server logic behind protocols: CommandRouter, IPCServer, (later) WindowManager, Animator, Backend protocols
  MWMPlatform/ real macOS implementations: AX, NSWorkspace, NSScreen, display link   (added in M2)
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
- [x] `swift format lint --strict` is clean. `swiftlint` is **not installed**, so that check from `docs/coding-guidelines.md` has not been run (`brew install swiftlint` if wanted).
- [ ] Stable code signing for Accessibility (**deferred to M2**, see open items)

### M2. AX spike and window discovery
Add MWMPlatform: permission prompt, window enumeration, live observers (created, destroyed, focused, moved), `mwm list`. FakeBackend tests for registry bookkeeping.

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
Implemented so far: `ping`.

## Open items
- **Code signing.** No signing identity exists on this machine. macOS ties the Accessibility permission to the binary's code identity, so rebuilds with ad-hoc signatures may need the permission granted again. Before M2: create a self-signed code-signing certificate (e.g. `mwm-dev`) in Keychain Access, then `make install SIGN_ID=mwm-dev`. This changes the keychain, so it needs the user's go-ahead.
- Native fullscreen windows are left alone. Terminals that snap to character cells won't fill their frame exactly.
- AX calls cost one round trip per window, so a slide with many windows may be coarse (see M4).

- **Testing pitfalls found in M1.** (1) Tests that block in `read()` must not run on Swift concurrency's cooperative pool: a task-group version of the concurrent-clients test failed ~80% of runs, plain threads pass. The cause is suspected, not verified. (2) A test that writes more than the socket buffer (~8 KB) on the same thread that later reads will deadlock. (3) macOS has no `timeout`; use `perl -e 'alarm N; exec @ARGV' cmd` to bound a run.

- **Guideline conflict: GCD.** `docs/coding-guidelines.md` says not to use new GCD APIs. `IPCServer` uses `Thread`, `DispatchQueue` and `DispatchSemaphore` (accept loop, worker queue), and `mwmd/main.swift` uses `DispatchSource` for signals and `dispatchMain()`. The reason is that the server does blocking POSIX I/O, which doesn't belong on Swift concurrency's cooperative pool (see the testing pitfall above). Decide whether to keep this, or move to `Network.framework` or an actor-based design, before M2 builds on it.

## Log
- 2026-10-08: M1 built. MWMPlatform is not created yet (an empty target would be noise); it arrives with M2.
