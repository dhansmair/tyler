# One connection per app

## Context

The platform's window code is sliced by mechanism, not responsibility. `AXBackend`
(`Sources/TylerPlatform/AXBackend.swift`, 391 lines, at SwiftLint's limit) joins six pieces by
process ID: `TrackedWindows`, `AppObserver`, `StepWriter` and `AppWriteQueue`,
`UnresponsiveApps`, `PendingReads`. To follow how tylerd talks to one app, a reader has to join
them in their head. The name `AXBackend` also names a detail of the bottom layer, though most of
the class is running apps, attaching, routing and focus.

**Goal:** code a human reads top-down, in layers, each named after its responsibility:
- the domain (unchanged)
- `SystemWindowBackend`: all apps
- `AppConnection`: one app
- the raw calls at the bottom

The other aims:
- **Mockable Accessibility:** for the first time, the attach, notification, move and timeout
  logic gets unit tests.
- **No behaviour change.** `WindowBackend` stays as it is, so the server doesn't notice.
- **Timing:** before the alpha (`plans/alpha-release.md`, "Structure").

## The layers

```
WindowManager, controllers      domain: windows, apps, workspaces, displays, layouts
        │  WindowBackend (protocol, unchanged)
SystemWindowBackend             all apps: which run, attaching and retrying, the routing index
        │                       (window → app), the focused window, the event stream
AppConnection (one per app)     one app: its windows (TrackedWindows), reading them, pending
        │                       reads, its notifications turned into events, moving (its own
        │                       step queue), focusing and closing, whether it answers
AXBridge                        the typed AX vocabulary: windows, frames, writes (size,
        │                       position, size), raise, close, the batched reads
AXClient / WorkspaceClient      the seams: dumb, one-to-one wrappers of the C Accessibility API
                                and of NSWorkspace; no tyler logic. Real: SystemAXClient,
                                SystemWorkspaceClient. Plus AppWriteQueue, the step queue
```

**The naming rule** (it goes into `devdocs/architecture.md`): a type is named after its
responsibility; only the lowest layer, whose responsibility is a technology, is named after it.
- `AXBackend` → `SystemWindowBackend`
- `CGWindowStacking` → `SystemWindowStacking`
- `AXBridge` keeps its name.

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
  - The real one is `SystemAXClient`. `AXBridge` becomes a struct over an `AXClient`, with the
    same typed functions as now.
- **`WorkspaceClient`**: `NSWorkspace` and `NSRunningApplication`, one to one: the running
  apps (process ID, activation policy, name, bundle ID), the frontmost app, tylerd's own process
  ID, and the launched, activated and quit events. The real one is `SystemWorkspaceClient`, which
  absorbs `RunningAppsObserver`.
- **The fakes** (`Tests/TylerPlatformTests/Apps/`):
  - **`FakeAXClient`:** a small AX emulator holding attributes per element, with application
    elements as stand-ins, as `TrackedWindowsTests` already does, and a lock for the queue
    threads. Typed helpers keep the tests in window words:
    `addWindow(id:frame:subrole:buttons:in:)`, `post(_:for:)`,
    `answer(_ error:, from:)` for `cannotComplete` or `invalidUIElement`, `clamp(size:)`.
  - **`FakeWorkspaceClient`:** apps launching, activating and quitting.
- **The retry delay** goes through an injected `Clock`, so the tests can drive the 6 × 500 ms
  attach retries. `TestClock` and `settle()` are reused from `Tests/TylerTestSupport/`, which
  `TylerPlatformTests` then depends on (`Package.swift`).

**Existentials:** the backend and the connections hold `any AXClient`. That's the readable
choice. Every call through it is an IPC round trip to an app, which costs milliseconds, so
dynamic dispatch is noise, the per-frame steps included. This is a deliberate exception to
"keep the hot paths free of existentials", to be written next to the protocol.

## Who owns what

| State | Owner |
|---|---|
| A window's element, last read, pending read depth (`TrackedWindows`, `PendingReads`, per app) | `AppConnection` |
| The app's notifications (registered through `AXClient`) | `AppConnection` |
| The step queue (`AppWriteQueue`), when the app last timed out | `AppConnection` |
| The routing index `[WindowID: pid_t]`, changed only by the connections' reports | `SystemWindowBackend` |
| The focused window, `unfocus` (tylerd frontmost) | `SystemWindowBackend` |
| Attaching, retries, quitting (the events of `WorkspaceClient`) | `SystemWindowBackend` |

**How a connection reports:** it reports to a closure, and holds no reference back. Its reports
are created, updated, destroyed and "the app's focused window is now X". The backend turns
them into `WindowEvent`s and sets `isFocused` on outgoing `WindowInfo`s. That's one place, so
the connection never needs to know about focus across apps. **What the connection must not
learn:** workspaces, layouts, app assignments.

## Folder (decided)

The new layer is `Sources/TylerPlatform/Apps/`, holding:
- the backend: `SystemWindowBackend` (+`FreshWindows`, +`Moving`)
- the connection: `AppConnection` (+`Moving`, +`Notifications`), `TrackedWindows`,
  `PendingReads`, `AppWriteQueue`
- the AX vocabulary and the seams: `AXBridge`, `WindowInfo+AX`, `AXClient`, `SystemAXClient`,
  `WorkspaceClient`, `SystemWorkspaceClient`

The pointer, display and stacking files stay flat for now, and the tests mirror the folder.
`devtools/check-test-paths` and SwiftLint's `file_name` rule check it.

## Steps

Each step is one commit with `make check` green and no change in behaviour. The test order uses
the seam: first make today's backend mockable, then pin down what it does in tests at the
`WindowBackend` boundary, then restructure underneath without changing those tests.

1. **Claim.** Put the work on the "In progress" line of `devdocs/REFACTORING.md`.
2. **Renames and folder.** `git mv` only:
   - `AXBackend` → `SystemWindowBackend`, with `+FreshWindows` and `AXBackendTests`.
   - `CGWindowStacking` → `SystemWindowStacking`.
   - The window files move into `Apps/`.
   - References follow: `Sources/tylerd/main.swift`, the doc comments of
     `TylerServer/Backend/WindowBackend.swift` and `WindowStacking.swift`, `TrackedWindows`,
     `devtools/LiveCheck/Pointer.swift`, `CLAUDE.md` (Layout), `devdocs/architecture.md` (the
     diagram), `macos-behaviour.md`, `known-issues.md`, `testing.md`, the plans.
3. **The seams.** Add `AXClient` and `SystemAXClient`. The latter absorbs `AppObserver`'s
   observer, callback and run loop source; its "already registered is harmless" rule moves up
   into the caller. `AXBridge` becomes a struct over an `AXClient`. Add `WorkspaceClient` and
   `SystemWorkspaceClient`; the latter absorbs `RunningAppsObserver`. `SystemWindowBackend`
   takes both clients and a clock in `init` (defaults: the real ones) and calls only through
   them. Mechanical; no tests change, except `AXBridge`'s callers passing a client.
4. **Tests of today's behaviour** through `WindowBackend`, with `FakeWorkspaceClient` and
   `FakeAXClient`, in
   `Tests/TylerPlatformTests/Apps/SystemWindowBackendTests+<Aspect>.swift`:
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
5. **`AppConnection`: windows, reading, notifications.** Move into it:
   - its `TrackedWindows` and `PendingReads`
   - `register`, `forget`, `handle`, `readPending`, `readFocus`, the `invalidUIElement` handling
   - the per-app part of `freshWindows`

   The backend keeps a `[pid_t: AppConnection]` and the routing index. No test changes. Live
   check: an app launching, a window opened and closed, a window minimized, `tyler debug
   windows`.
6. **`AppConnection`: moving and answering.** The connection takes over:
   - its own `AppWriteQueue`, from `StepWriter`'s per-app part
   - the last timeout (`UnresponsiveApps` becomes a single instant)
   - `setFrame`, `setPosition`, `setFrameStep`, `setFrameInPassing` and settling

   The backend sums `takeQueuedWrites` over the connections, and `StepWriter` and
   `UnresponsiveApps` go away. Their unit tests (`StepWriterTests`, `UnresponsiveAppsTests`) are
   replaced by the step-4 tests that cover the same behaviour; check each case has a twin before
   deleting. Live check: slide, swipe, drag resize, the swap animation, `kill -STOP` skipping.
7. **`AppConnection`: focus and close.** `focus` and `close` route to the connection, and the
   backend keeps `unfocus` and the focused window. Live check: cmd-tab to a parked window,
   `window close`, focus follows mouse.
8. **Docs and cleanup:**
   - `devdocs/architecture.md`: the layers, the naming rule, the existential exception.
   - `devdocs/design.md`: the decisions that last.
   - `CLAUDE.md`: Layout, the TylerPlatform line, and "not unit tested" becoming "unit tested
     through `AXClient` and `WorkspaceClient`".
   - `devdocs/testing.md` items touched.
   - Delete `plans/app-connection.md`, tick `plans/alpha-release.md`, clear the claim.

## Files

- **New:** `Apps/AppConnection.swift` (+`+Moving`, `+Notifications`), `Apps/AXClient.swift`,
  `Apps/SystemAXClient.swift`, `Apps/WorkspaceClient.swift`, `Apps/SystemWorkspaceClient.swift`;
  `Tests/TylerPlatformTests/Apps/FakeAXClient.swift` and `FakeWorkspaceClient.swift`, plus
  `SystemWindowBackendTests+…` and `AXBridgeTests`.
- **Changed:** `SystemWindowBackend.swift` (ex `AXBackend.swift`), `TrackedWindows.swift`
  (per-app doc), `AXBridge.swift` (a struct over a client), `Package.swift`
  (`TylerPlatformTests` → `TylerTestSupport`), `Sources/tylerd/main.swift`.
- **Removed:** `AppObserver.swift` and `RunningAppsObserver.swift` (step 3, into the real
  clients); `StepWriter.swift`, `UnresponsiveApps.swift` and their tests (step 6).
- **Reused:** `AppWriteQueue`, `FrameWrite.inPassing`, `CGRect.clearingOrigin`,
  `WindowInfo.read`, `WindowInfo.logName`, `TestClock`, `settle()`.

## Verification

- `make check` after every commit; step 4's tests stay unchanged through steps 5–7, which is
  the proof of no behaviour change.
- Mutation check for step 4: break the guarded code, see the test fail, put it back.
- After steps 5–7, the `live-check` skill on real windows, with `tyler restart` from the main
  checkout. Check the screen isn't locked first. Target test windows by id, using a scratch
  TextEdit file document and `kill -STOP`/`-CONT`.
- At the end: `wc -l` shows no file near 400 lines, `AXBackend` appears nowhere
  (`grep -rn AXBackend`), and `tyler status` and a day of normal use show nothing new in
  `~/.tyler/tyler.log` at `warning`.

## Working alongside

This touches every file of the window code in TylerPlatform. Before starting, check
`REFACTORING.md`'s "In progress" line and `plans/` for open work there. If a second agent starts
meanwhile, it works in a worktree (`CLAUDE.md`, Parallel agents). Land only when the main
checkout is clean and on `main` (`git diff --quiet && git diff --cached --quiet`, no untracked
files).
