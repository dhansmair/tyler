# One connection per app

## Why

TylerPlatform's window code is sliced by mechanism, not by responsibility. To follow how tylerd
talks to one app, a reader joins six pieces by process ID in their head:

| Piece | What it knows | Keyed by |
|---|---|---|
| `TrackedWindows` | each window's Accessibility element and app | window |
| `AppObserver` | an app's notifications | app |
| `StepWriter`, `AppWriteQueue` | the steps of a motion in flight | app |
| `UnresponsiveApps` | whether an app answers | app |
| `PendingReads` | which windows to read again after a burst | window |
| `AXBackend` | all of the above, plus attaching, retries, focus and routing | all |

`AXBackend` shows it: it reached SwiftLint's 400-line limit, and code was moved out of it
(`RunningAppsObserver`) to make room rather than to give it an owner. Its name also names a
detail of its bottom layer: most of it (running apps, attaching, routing, focus) isn't
Accessibility.

The goal is code a human reads top-down, in layers: technical details at the bottom, the logical
parts (apps, windows) above, each layer speaking the words of the one above it. No behaviour
changes: the `WindowBackend` protocol stays as it is, and the server doesn't notice.

## The layers

```
WindowManager, controllers      the domain: windows, apps, workspaces, displays, layouts
        │  WindowBackend (protocol, unchanged)
SystemWindowBackend             all apps: which run, attaching them (and retrying), which app a
        │                       window belongs to, which window has focus, the event stream
AppConnection (one per app)     one app: its windows, reading them, moving them (the step queue),
        │                       focusing and closing them, whether the app answers, its
        │                       notifications turned into window events
AppAccess → AXBridge,           technical: the raw Accessibility calls for one app, the queue
AppWriteQueue
```

**The naming rule:** a type is named after its responsibility; only the lowest layer, whose
responsibility is a technology, is named after it. `AXBridge` stays; `AXBackend` becomes
`SystemWindowBackend`, as `SystemPointerInput` and `SystemAccessibilityGate` are named
("System": the real macOS implementation, not the fake). `CGWindowStacking` becomes
`SystemWindowStacking` for the same reason.

## Who owns what

| State | Owner | Why there |
|---|---|---|
| A window's element, its last read, whether it needs reading again | its `AppConnection` | a window belongs to exactly one app for its whole life |
| The step queue, whether the app answers | `AppConnection` | macOS answers per app, on the app's main thread: one slow app, all its windows |
| The app's notifications | `AppConnection` | an `AXObserver` is per process |
| Which app a window belongs to (the routing index) | `SystemWindowBackend` | a command names a window, not an app. The index only says where to ask, and changes only through the connections' events, so it never becomes a second list of windows |
| Which window has focus | `SystemWindowBackend` | focus moves between apps, and `unfocus` makes tylerd itself frontmost |
| Attaching, retries, quitting | `SystemWindowBackend` | an app that doesn't answer yet has no connection |

**What the connection must not learn:** anything of the domain above windows (workspaces,
layouts, app assignments). It knows windows, frames and notifications. Per-window objects inside
it are plain data, not types with behaviour of their own: what an app does (answering, or not),
it does for all its windows.

## The test seam

TylerPlatform has no unit tests for its trickiest logic (attach retries, forgetting a window on
`invalidUIElement`, skipping an app that timed out, reading once after a burst). `AppConnection`
reaches the app through a protocol, `AppAccess`: the calls one app needs (its windows, a window's
attributes, writing a position or frame, raising, pressing close, registering notifications). The
real one, `AXAppAccess`, is a thin layer over `AXBridge`; tests use a fake app. The connection is
generic over it (`AppConnection<Access: AppAccess>`), so the step path stays free of existentials.
That is the protocol's test seam (`CLAUDE.md`, "Abstractions earn their place").

## Decisions

| # | Question | Decision |
|---|----------|----------|
| D1 | Granularity | **Per app.** An app answers every Accessibility call for all its windows on one thread, so a per-window owner adds no parallelism and would split what the app does as a whole (being hung). |
| D2 | Names | `SystemWindowBackend`, `AppConnection`, `AppAccess` and `AXAppAccess`; `SystemWindowStacking`. ("Handler" says nothing about what it is; "app" is a word users see, in `[apps]`.) |
| D3 | How a connection reports | It returns what happened, or calls one closure the backend gives it; it holds no reference back to the backend (`CLAUDE.md`, "Dependencies point one way"). |
| D4 | Threads | Unchanged: on the main actor, with the step queue inside the connection. Moving more calls off the main thread is a separate decision, after the measurement in `devdocs/REFACTORING.md`. |

## Steps

Each a commit with `make check` green and no behaviour change. The code is untested today, so
each step that moves behaviour first covers it with tests through the seam, then moves it, then
is checked on real windows (`live-check`).

- [ ] This plan.
- [ ] Renames: `AXBackend` → `SystemWindowBackend` (and `+FreshWindows`), `CGWindowStacking` →
  `SystemWindowStacking`; `CLAUDE.md` (Layout), `devdocs/architecture.md`, the skills.
- [ ] `AppAccess` and `AXAppAccess`, and the fake app in the tests; nothing uses it yet.
- [ ] `AppConnection` holding its windows and reading them: `TrackedWindows` (per app),
  `WindowInfo+AX`, `PendingReads` move in; registering a window, forgetting one on
  `invalidUIElement`. Tests through the fake.
- [ ] Moving: the step queue (`StepWriter`'s per-app part) and `UnresponsiveApps` move in;
  `setFrame`, the steps, `setFrameInPassing`. Tests: settling, skipping an app that timed out.
- [ ] Notifications: `AppObserver` belongs to the connection, and `handle` becomes the
  connection turning notifications into window events.
- [ ] Focusing and closing through the connection; `SystemWindowBackend` keeps the focused
  window, the routing index, attaching and retries, and `RunningAppsObserver`.
- [ ] Docs: `devdocs/architecture.md` (the layers, the naming rule), `devdocs/design.md` (the
  decisions that last), `CLAUDE.md` (Layout); the live checks of `devdocs/testing.md` that touch
  apps (attach, a hung app, a restart, a window closed without a notification). Then delete this
  plan.

## Working alongside

This touches `AXBackend` and `StepWriter`, which the swap animations (`tyler-animate-swaps`)
changed recently. Claim it in `devdocs/REFACTORING.md` before starting, and check that no other
work is open on TylerPlatform.
