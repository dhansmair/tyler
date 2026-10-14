# One connection per app

## Context

The platform's window code is sliced by mechanism, not responsibility. `AXBackend`
(`Sources/TylerPlatform/AXBackend.swift`, 391 lines, at SwiftLint's limit) joins six pieces by
process ID: `TrackedWindows`, `AppObserver`, `StepWriter` and `AppWriteQueue`,
`UnresponsiveApps`, `PendingReads`. To follow how tylerd talks to one app, a reader has to join
them in their head. The names don't help either: `AXBackend` names a detail of its bottom layer
(most of the class is running apps, attaching, routing and focus), and "backend", for the port
and its folder, says nothing about what is behind it.

**Goal:** code a human reads top-down, in layers, each named after its responsibility:
- the domain (unchanged)
- the window system (`WindowSystem`, the port), implemented by `MacWindowSystem`: all apps
- `AppConnection`: one app
- the raw calls at the bottom

The other aims:
- **Mockable Accessibility:** for the first time, the attach, notification, move and timeout
  logic gets unit tests.
- **No behaviour change.** The port keeps its requirements, only its name changes, so the server
  only sees the renames.
- **Timing:** before the alpha (`plans/alpha-release.md`, "Structure").

## Names

**The naming rules** (they go into `devdocs/architecture.md` and `CLAUDE.md`):
- **Responsibility, not technology.** A type is named after its responsibility; only the lowest
  layer, whose responsibility is a technology, is named after it (`AXBridge`, `AXClient`).
- **The real implementation of a port is `Mac<Port>`**; its fake in the tests is `Fake<Port>`.
  "Mac" says it is the macOS one, and nothing about how it works.
- **Ports live in `TylerServer/Ports/`**, as `devdocs/architecture.md` already calls them. In
  TylerPlatform, **one folder per port**, named after the port, holds its real implementation
  and everything only that implementation uses.

| Now | Then |
|---|---|
| `TylerServer/Backend/` | `TylerServer/Ports/` (the protocols, and `WindowEvent`, `PointerEvent`, `PointerWatch`, which they speak) |
| `WindowBackend` (protocol) | `WindowSystem` |
| `BackendError` | `WindowSystemError` |
| `WindowManager`'s `backend` (and `WindowMover`'s, the harness's `harness.backend`) | `windowSystem` |
| `AXBackend` (+`FreshWindows`) | `MacWindowSystem`, in `TylerPlatform/WindowSystem/` |
| `SystemPointerInput` | `MacPointerInput`, in `TylerPlatform/PointerInput/`, with the taps (`MouseButtonInterceptor`, `PointerMoveListener`, `TrackpadGestureListener`) |
| `ScreenDisplayProvider` | `MacDisplayProvider`, in `TylerPlatform/DisplayProvider/` |
| `CGWindowStacking` | `MacWindowStacking`, in `TylerPlatform/WindowStacking/` |
| `SystemAccessibilityGate` | `MacAccessibilityGate`, in `TylerPlatform/AccessibilityGate/` |
| `GapCursorWindow` | `MacGapCursor`, in `TylerPlatform/GapCursor/` |
| `FakeBackend` (+`UserMoves`) | `FakeWindowSystem` |
| (new) | `AXClient` / `MacAXClient`, `WorkspaceClient` / `MacWorkspaceClient` (see the seams) |

`FakeDisplays`, `FakePointer`, `FakeStacking`, `FakeGate` and `FakeGapCursor` stay as they are:
they already name their port. `TextEditor` (not a port) stays at the top of TylerPlatform.

## The layers

```
WindowManager, controllers      domain: windows, apps, workspaces, displays, layouts
        │  WindowSystem (the port, in TylerServer/Ports/)
MacWindowSystem                 all apps: which run, attaching and retrying, the routing index
        │                       (window → app), the focused window, the event stream
AppConnection (one per app)     one app: its windows (TrackedWindows), reading them, pending
        │                       reads, its notifications turned into events, moving (its own
        │                       step queue), focusing and closing, whether it answers
AXBridge                        the typed AX vocabulary: windows, frames, writes (size,
        │                       position, size), raise, close, the batched reads
AXClient / WorkspaceClient      the seams: dumb, one-to-one wrappers of the C Accessibility API
                                and of NSWorkspace; no tyler logic. Real: MacAXClient,
                                MacWorkspaceClient. Plus AppWriteQueue, the step queue
```

## The two seams: dumb clients

These are the protocols the tests mock, allowed by the guidelines as test seams. Each forwards
one to one and holds no tyler logic, so all the logic above them is testable, `AXBridge`'s
included.

- **`AXClient`** (`Sendable`: the steps write from the per-app queues): the C Accessibility API
  tylerd uses, and nothing else.
  - Elements: create the application element, the system-wide element; set the messaging
    timeout.
  - Reading: copy an attribute, copy several attributes; the window number
    (`_AXUIElementGetWindow`).
  - Writing: set an attribute, perform an action.
  - Notifications: register one on an element, with a handler. The real one keeps the
    `AXObserver`, its C callback and the main run loop source, which is what `AppObserver` does
    today.
  - The real one is `MacAXClient`. `AXBridge` becomes a struct over an `AXClient`, with the same
    typed functions as now.
- **`WorkspaceClient`**: `NSWorkspace` and `NSRunningApplication`, one to one: the running
  apps (process ID, activation policy, name, bundle ID), the frontmost app, tylerd's own process
  ID, and the launched, activated and quit events. The real one is `MacWorkspaceClient`, which
  absorbs `RunningAppsObserver`.
- **The fakes** (`Tests/TylerPlatformTests/WindowSystem/`):
  - **`FakeAXClient`:** a small AX emulator holding attributes per element, with application
    elements as stand-ins, as `TrackedWindowsTests` already does, and a lock for the queue
    threads. Typed helpers keep the tests in window words:
    `addWindow(id:frame:subrole:buttons:in:)`, `post(_:for:)`,
    `answer(_ error:, from:)` for `cannotComplete` or `invalidUIElement`, `clamp(size:)`.
  - **`FakeWorkspaceClient`:** apps launching, activating and quitting.
- **The retry delay** goes through an injected `Clock`, so the tests can drive the 6 × 500 ms
  attach retries. `TestClock` and `settle()` are reused from `Tests/TylerTestSupport/`, which
  `TylerPlatformTests` then depends on (`Package.swift`).

**Existentials:** `MacWindowSystem` and the connections hold `any AXClient`. That's the readable
choice. Every call through it is an IPC round trip to an app, which costs milliseconds, so
dynamic dispatch is noise, the per-frame steps included. This is a deliberate exception to
"keep the hot paths free of existentials", to be written next to the protocol.

## Who owns what

| State | Owner |
|---|---|
| A window's element, last read, pending read depth (`TrackedWindows`, `PendingReads`, per app) | `AppConnection` |
| The app's notifications (registered through `AXClient`) | `AppConnection` |
| The step queue (`AppWriteQueue`), when the app last timed out | `AppConnection` |
| The routing index `[WindowID: pid_t]`, changed only by the connections' reports | `MacWindowSystem` |
| The focused window, `unfocus` (tylerd frontmost) | `MacWindowSystem` |
| Attaching, retries, quitting (the events of `WorkspaceClient`) | `MacWindowSystem` |

**How a connection reports:** it reports to a closure, and holds no reference back. Its reports
are created, updated, destroyed and "the app's focused window is now X". `MacWindowSystem` turns
them into `WindowEvent`s and sets `isFocused` on outgoing `WindowInfo`s. That's one place, so the
connection never needs to know about focus across apps. **What the connection must not learn:**
workspaces, layouts, app assignments.

## The folder

`Sources/TylerPlatform/WindowSystem/` holds:
- the port's implementation: `MacWindowSystem` (+`FreshWindows`, +`Moving`)
- the connection: `AppConnection` (+`Moving`, +`Notifications`), `TrackedWindows`,
  `PendingReads`, `AppWriteQueue`
- the AX vocabulary and the seams: `AXBridge`, `WindowInfo+AX`, `AXClient`, `MacAXClient`,
  `WorkspaceClient`, `MacWorkspaceClient`

The tests mirror it (`Tests/TylerPlatformTests/WindowSystem/`); `devtools/check-test-paths` and
SwiftLint's `file_name` rule check it.

## Steps

Each step is one commit with `make check` green and no change in behaviour. The renames come
first, each mechanical and on its own, so the restructuring after them reads in the new words.
The test order then uses the seam: first make today's window system mockable, then pin down
what it does in tests at the port, then restructure underneath without changing those tests.

1. **Claim.** Put the work on the "In progress" line of `devdocs/REFACTORING.md`.
2. **The port's folder:** `TylerServer/Backend/` → `TylerServer/Ports/` (`git mv`), and the
   test paths that mirror it.
3. **The window port:** `WindowBackend` → `WindowSystem`, `BackendError` → `WindowSystemError`,
   `FakeBackend` → `FakeWindowSystem` (+`UserMoves`), across the server, the harness and the
   tests.
4. **The property:** `backend` → `windowSystem` in `WindowManager`, `WindowMover` and their
   initializers (25 uses in 6 files), and `harness.backend` → `harness.windowSystem` in the tests
   (about 500 uses in 46 files; a whole-word replace, then a read of the diff).
5. **The real implementations and their folders:** `AXBackend` → `MacWindowSystem` in
   `TylerPlatform/WindowSystem/`, with the window files; `SystemPointerInput`,
   `ScreenDisplayProvider`, `CGWindowStacking`, `SystemAccessibilityGate` and `GapCursorWindow`
   → `Mac…`, each in its port's folder (see Names). The tests move with them.
   - References follow: `Sources/tylerd/main.swift`, the doc comments of the ports,
     `devtools/LiveCheck/Pointer.swift`, `CLAUDE.md` (Layout, and the commands that name
     types), `devdocs/architecture.md` (the diagram), `macos-behaviour.md`, `known-issues.md`,
     `testing.md`, the skills, the plans.
   - Log categories (`ax`, `pointer`, …) stay: they say what a line is about, not which type
     wrote it.
6. **The seams.** Add `AXClient` and `MacAXClient`. The latter absorbs `AppObserver`'s
   observer, callback and run loop source; its "already registered is harmless" rule moves up
   into the caller. `AXBridge` becomes a struct over an `AXClient`. Add `WorkspaceClient` and
   `MacWorkspaceClient`; the latter absorbs `RunningAppsObserver`. `MacWindowSystem` takes both
   clients and a clock in `init` (defaults: the real ones) and calls only through them.
   Mechanical; no tests change.
7. **Tests of today's behaviour** through `WindowSystem`, with `FakeWorkspaceClient` and
   `FakeAXClient`, in `Tests/TylerPlatformTests/WindowSystem/MacWindowSystemTests+<Aspect>.swift`:
   - **Attach:** windows are created; a refusal is retried, gives up after 6, and is attached
     again when the app comes to the front; quitting drops the app's windows.
   - **Notifications:** created and destroyed; a burst of moves read once; minimized read at
     once; a dropped read logged; focus changes, and `readFocus` for an app that attaches while
     frontmost.
   - **Moving:**
     - `setFrame`: one write when the size matches; a clamped size reported; moving first when
       the window reached past its frame.
     - steps through the queue, and settling before `setFrame`.
     - `setFrameInPassing`, `setFrameStep`.
   - **Failures:** `invalidUIElement` forgets the window; `cannotComplete` skips the app for 5 s
     (moves and focus); the reason without the action (the `refusal` test moves here).
   - **Other:** `freshWindows`.
   - **`AXBridge` itself** (`AXBridgeTests`): the size–position–size order of `setFrame`, raise
     (frontmost, raise, main), close through the close button (and refused without one), the
     batched read with a missing attribute, the title-bar buttons.

   Check that each test can fail by breaking the guarded code. Split into a few commits by
   aspect if large.
8. **`AppConnection`: windows, reading, notifications.** Move into it:
   - its `TrackedWindows` and `PendingReads`
   - `register`, `forget`, `handle`, `readPending`, `readFocus`, the `invalidUIElement` handling
   - the per-app part of `freshWindows`

   `MacWindowSystem` keeps a `[pid_t: AppConnection]` and the routing index. No test changes.
   Live check: an app launching, a window opened and closed, a window minimized, `tyler debug
   windows`.
9. **`AppConnection`: moving and answering.** The connection takes over:
   - its own `AppWriteQueue`, from `StepWriter`'s per-app part
   - the last timeout (`UnresponsiveApps` becomes a single instant)
   - `setFrame`, `setPosition`, `setFrameStep`, `setFrameInPassing` and settling

   `MacWindowSystem` sums `takeQueuedWrites` over the connections, and `StepWriter` and
   `UnresponsiveApps` go away. Their unit tests (`StepWriterTests`, `UnresponsiveAppsTests`) are
   replaced by the step-7 tests that cover the same behaviour; check each case has a twin before
   deleting. Live check: slide, swipe, drag resize, the swap animation, `kill -STOP` skipping.
10. **`AppConnection`: focus and close.** `focus` and `close` route to the connection, and
    `MacWindowSystem` keeps `unfocus` and the focused window. Live check: cmd-tab to a parked
    window, `window close`, focus follows mouse.
11. **Docs and cleanup:**
    - `devdocs/architecture.md`: the layers, the naming rules, the existential exception.
    - `devdocs/design.md`: the decisions that last.
    - `CLAUDE.md`: Layout (`Ports/`, the TylerPlatform folders), the naming rules under Design
      principles, and "not unit tested" becoming "unit tested through `AXClient` and
      `WorkspaceClient`".
    - `devdocs/testing.md` items touched.
    - Delete this plan, tick `plans/alpha-release.md`, clear the claim.

## Files

- **New:** `WindowSystem/AppConnection.swift` (+`+Moving`, `+Notifications`),
  `WindowSystem/AXClient.swift`, `MacAXClient.swift`, `WorkspaceClient.swift`,
  `MacWorkspaceClient.swift`; `Tests/TylerPlatformTests/WindowSystem/FakeAXClient.swift` and
  `FakeWorkspaceClient.swift`, plus `MacWindowSystemTests+…` and `AXBridgeTests`.
- **Renamed or moved:** everything in the Names table; the ports from `TylerServer/Backend/` to
  `Ports/`.
- **Changed:** `MacWindowSystem.swift` (ex `AXBackend.swift`), `TrackedWindows.swift` (per-app
  doc), `AXBridge.swift` (a struct over a client), `Package.swift` (`TylerPlatformTests` →
  `TylerTestSupport`), `Sources/tylerd/main.swift`.
- **Removed:** `AppObserver.swift` and `RunningAppsObserver.swift` (step 6, into the real
  clients); `StepWriter.swift`, `UnresponsiveApps.swift` and their tests (step 9).
- **Reused:** `AppWriteQueue`, `FrameWrite.inPassing`, `CGRect.clearingOrigin`,
  `WindowInfo.read`, `WindowInfo.logName`, `TestClock`, `settle()`.

## Verification

- `make check` after every commit; step 7's tests stay unchanged through steps 8–10, which is
  the proof of no behaviour change.
- The renames (steps 2–5) change no logic: their diffs are reviewed as renames only, and a
  `tyler restart` after step 5 shows the windows where they were.
- Mutation check for step 7: break the guarded code, see the test fail, put it back.
- After steps 8–10, the `live-check` skill on real windows, with `tyler restart` from the main
  checkout. Check the screen isn't locked first. Target test windows by id, using a scratch
  TextEdit file document and `kill -STOP`/`-CONT`.
- At the end: `wc -l` shows no file near 400 lines; none of the old names (`AXBackend`,
  `WindowBackend`, `BackendError`, `FakeBackend`, `SystemPointerInput`, `ScreenDisplayProvider`,
  `CGWindowStacking`, `SystemAccessibilityGate`, `GapCursorWindow`) appears in `Sources/`,
  `Tests/`, `devtools/`, the docs or the skills; and `tyler status` and a day of normal use show
  nothing new in `~/.tyler/tyler.log` at `warning`.

## Working alongside

The renames touch most of the server and nearly every test file, and the rest touches every file
of the window code in TylerPlatform. Before starting, check `REFACTORING.md`'s "In progress" line
and `plans/` for open work, and agree on a quiet moment for steps 2–5 with any other agent: its
open branches would conflict with them everywhere. If a second agent starts meanwhile, it works in
a worktree (`CLAUDE.md`, Parallel agents). Land only when the main checkout is clean and on `main`
(`git diff --quiet && git diff --cached --quiet`, no untracked files).
