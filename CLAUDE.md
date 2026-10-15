# tyler

A personal window manager for macOS, written in Swift. It replaces AeroSpace and Amethyst for one specific workflow:

- **xmonad-style tiling.** Each workspace is an ordered *list* of windows with a clear prev/next and a master (the first window). Typical use is two windows side by side, or one on the left and two stacked on the right. New layouts must be easy to add.
- **Workspaces side by side in a row**, like pages. You move left and right between them, and the view snaps to one. Each physical display has its own row.
- **Server plus CLI.** `tylerd` runs in the background and owns all window state. `tyler` is a small client that sends one command and prints the reply. Hotkeys are not built in: bind keys to `tyler` commands with skhd, Karabiner or Raycast.

Windows are controlled through the macOS Accessibility API (no SIP changes). Workspaces work by parking the windows of inactive workspaces just past an edge of their display that touches no other display (the right edge, or the left one if a display lies to the right), and switching slides horizontally: macOS won't let a window leave through the top or bottom of the screen (measured; see `Parking` and `devdocs/macos-behaviour.md`). Nothing slides onto another display: on a display with a neighbour beside it, switches are instant.

**Terms:** a *display* is a physical screen; a *workspace* is one page of a display's row of workspaces. Don't use "monitor" for a screen, in code or docs (AppKit's event monitor API keeps its name). `docs/manual.md` (Concepts) defines the user-facing terms.

## Status

**Keep this section current.** Whenever a feature is complete or its state changes (built, unit tested, checked against real windows, dropped), update it in the same commit.

Every feature in `docs/manual.md` is built and unit tested, and most are in daily use on real windows (`devdocs/testing.md` lists what hasn't been checked); the strip layout is **experimental** (`devdocs/strip-layout.md`: its state, known issues and open questions; keep it current when the strip changes). The next milestone is the first alpha release, 0.1.0: `plans/alpha-release.md` is the working document, so read it first and tick it off as work progresses.

Where things are written down:
- `devdocs/architecture.md`: the target architecture (the layers from input to effects, TylerCore's bounded contexts and which way their dependencies point, the rules), with a diagram, and how far the code is from it. Read it before adding a type, a folder or a dependency between parts.
- `devdocs/design.md`: the design decisions and why. Add a decision when it is made.
- `devdocs/macos-behaviour.md`: what macOS was measured to do (parking limits, display changes, event taps). Record new measurements there.
- `devdocs/testing-strategy.md`: the three layers of tests (unit, scenario, end to end) and where a new test goes. Read it before writing a test.
- `devdocs/testing.md`: the checklist of checks against real windows, with what has been checked so far.
- `devdocs/known-issues.md`: bugs, limitations and what isn't built. Remove an item in the commit that fixes it, also from its user-facing twin `docs/known-issues.md`.
- `devdocs/REFACTORING.md`: the ranked refactoring and performance backlog.
- `docs/`: for users. `docs/manual.md` is the manual (concepts, running tylerd, the config file and the command reference); `layouts.md`, `features.md`, `keybindings.md`, `troubleshooting.md` and `known-issues.md` sit beside it. Keep them in step when behaviour, settings or commands change.
- `plans/`: the plan for each piece of work still to do, git-ignored (local working notes, not published); delete a plan once its work is done and its lasting decisions are in `devdocs/design.md`. Keep plans there, not in `~/.claude`.

## Layout

```
Sources/
  TylerRuntime/  tyler as a running program: TylerLog, Paths (the socket, log, state and config files), TylerVersion; TylerCore doesn't depend on it
  TylerCore/     the domain, pure, a folder per feature:
    Windows/, Displays/, Geometry/  what everything builds on: window types and Placement; display types and DisplayArrangement (numbers, neighbours, parking edges); geometry helpers
    Layouts/       the protocols, LayoutStates and LayoutKind in Layout.swift; a folder per layout with the layout and its state (Tall/TallLayout.swift, Tall/TallLayoutState.swift); what tall and grid share in Columns/; the strip, the only ScrollingLayout, in Strip/
    Workspaces/    Workspace (the ordered tiling list; the view of a scrolling layout in Workspace+View), WorkspaceRow, DisplayRows (a row per display, workspace homes, the focused display), WorkspaceSync (which windows each workspace holds), ScrollDirection, the command arguments (what commands talk about: ListTarget, WorkspaceTarget, DisplayTarget and the like, which the wire protocol carries)
    Placement/     where tiling puts each window on its display: Parking, TilingSnapshot (slots, windows in view, parking spots), Workspace+Parking, Reconciler (which windows are off from where they should be)
    Swipe/         the trackpad swipe: SwipeRecognizer (touches to travel), SwipeSession (where the windows go and where the swipe settles), OneEuroFilter, Snap
    Drag/          DragSession: what dragging a tiled window previews and what dropping it does (an arrival on another display, a resize, a move to another place)
    Pointer/       what the pointer is over and may do: PointerCheck, PointerFocus, a modifier+click or drag (ModifierKeys, ModifierGesture, ResizeEdges), a press in a gap (GapGrab)
    Motion/        animation tracks and easing, and the motion decided ahead: SlidePlan (a workspace switch), ScrollPlan, ViewScroll and ViewSnapshot (a scrolling layout's view), all giving a Transition
    Diagnostics/, Lifecycle/ (SavedState, the restart handover)
  TylerConfig/   Config and its sections, ConfigSource, the TOML parser and writer; above the domain, which it parses the file into
  TylerProtocol/ what tylerd and its clients agree on: Wire/ (requests, responses, ServerStatus, Unix sockets) and Indicator/ (IndicatorSnapshot and the Indicator protocol: what every menu bar item is given)
  TylerServer/   server logic around the @MainActor WindowManager, a folder per feature:
    Manager/       WindowManager (start, stop, the window events, `handle`), the controllers' shared types (Effect, Decision, Refusal, ControllerContext), running effects (+Effects: also laying out, focusing the current workspace, restoring original frames) and the command entries (+Commands: also beginCommand); the slide, swipe or drag in progress and how each ends in Interaction.swift
    Input/         WindowEventInterpreter: what a window event means (a move, a focus that is tylerd's own echo, a window closed, lists that may have changed)
    Tiling/        TilingController: the tiling commands (retile, focus, swap, float, close, tiling on|off) and reconcile (the lists after a window event)
    Model/         Model (the rows, the bookkeeping, whether tiling is on), WindowRegistry, WindowBookkeeping (floated windows, windows that have been on a workspace), keeping the lists in step with the windows and app assignments (SyncController)
    Motion/        the slide (Slide, +Slide), WindowMover (the one place that moves and focuses windows, with the original frames and the windows crossing to another display), Animator, Throttle (pacing steps), Debounce (acting once things are quiet: the pointer at rest, the displays settled)
    Workspaces/    WorkspaceController: switching workspaces with a slide, sending windows to another one, a focus change bringing a workspace into view; putting windows back (+Workspaces)
    Displays/ (DisplayController: the display commands, the displays settling, `window list`; display focus on the Model; following display changes), Layouts/ (LayoutController: the layout, ratio and strip size commands)
    Swipe/         SwipeController (how a swipe begins and where it settles); the swipe in progress (Swipe) and its pacing (+Swipe)
    Drag/          DragController (when a drag starts, its preview, following a resize, the drop; with the modifier too), the drag in progress (Drag) and its pacing (+Drag, +ModifierDrag)
    FocusFollowsMouse/  FocusFollowsMouseController, waiting for the pointer to rest
    GapCursor/     GapHover: the resize cursor over the gap under the pointer, and when it is checked again
    Pointer/       the pointer's events, each handed to its feature
    Config/        ConfigController (`config get|set`, what a new config changes), reading the file for `config reload`; Indicator/: menu bar updates; Diagnostics/: `tyler debug`; Lifecycle/: the restart handover
    IPC/           IPCServer, CommandRouter
    Ports/         the protocols in front of macOS (WindowSystem, PointerInput, WindowStacking, …) and the events they speak
  TylerIndicators/ the menu bar items behind the Indicator protocol: pure models (TextTitle, IndicatorMenu, WorkspaceMap), unit tested, and thin AppKit classes (TextIndicator, MapIndicator, IndicatorGroup, the shared MenuBuilder)
  TylerPlatform/ real macOS code, a folder per port with its real implementation `Mac<Port>` and what only it uses: WindowSystem/ (MacWindowSystem: all apps; AppConnection: one app, its windows, notifications, moves and step queue; AXBridge: the typed AX calls; AXClient and WorkspaceClient: the dumb seams over AX and NSWorkspace), PointerInput/ (MacPointerInput and the event taps: TrackpadGestureListener for swipes, PointerMoveListener for the pointer's moves, MouseButtonInterceptor for drags with the modifier), DisplayProvider/ (NSScreen), WindowStacking/ (the window under the pointer), AccessibilityGate/, GapCursor/ (the window that shows the resize cursor over a gap); the window system is unit tested through AXClient and WorkspaceClient, the rest isn't, so keep it thin
  TylerClient/   argv parsing, response formatting, IPC client
  tylerd/        server executable (thin)
  tyler/         CLI executable (thin)
devtools/      live-check: checks against real windows (see .claude/skills/live-check)
Tests/         one test target per library (TylerRuntimeTests, TylerCoreTests, TylerConfigTests, TylerProtocolTests, …) that mirrors its sources: `<Type>Tests.swift` or `<Type>Tests+<Aspect>.swift` beside where `<Type>.swift` is (TylerCoreTests/Layouts/Tall/TallLayoutTests+Resize.swift); TylerScenarioTests holds the scenario tests, a folder per feature of TylerServer (`Drag/SwapScenarios.swift`); TylerTestSupport holds what the server test targets share (the fakes, `ManagerHarness`)
```

Keep the executables thin. Logic goes in the libraries, and anything that touches macOS (AX, NSScreen, timers) goes behind a protocol so tests can use fakes.

## Commands

```bash
make build     # swift build
make test      # swift test with the flags below; use this, not plain `swift test`
make test-unit / make test-scenario   # one layer of tests (devdocs/testing-strategy.md)
make install   # release build, copied to ~/.local/bin (SIGN_ID=<identity> to codesign)
make lint      # swift format lint and swiftlint (with TOOLCHAIN_DIR set) over the whole tree
make check     # lint and test: what the pre-commit hook checks
```

- **Use `make test`.** The Command Line Tools ship Swift Testing, but SwiftPM doesn't find it without extra framework and rpath flags. The Makefile passes them.
- **Run the pieces by hand:** `.build/debug/tyler start` (background, log in `~/.tyler/tyler.log`) or `.build/debug/tylerd` in a terminal, then `.build/debug/tyler ping` or `tyler window list`. After `make build`, run `tyler restart`: a running `tylerd` keeps the old code, and `tyler status` warns about it. Restart keeps every window where it is (the old tylerd hands its workspaces over through `~/.tyler/tyler.state.json`); `stop` puts windows back. Set `TYLER_SOCKET=/tmp/x.sock` to use a different socket (default `~/.tyler/tyler.sock`).
- **`tyler window list` and the tiling commands need Accessibility permission.** Grant it in System Settings > Privacy & Security > Accessibility to the terminal app that runs `tylerd`. Without it, `tylerd` still runs and they print instructions. **Never suggest switching off or removing that grant while `tylerd` runs**: macOS can then stop all input until a forced restart (`devdocs/macos-behaviour.md`, "Events and taps"). Say `tyler stop` first.
- **`tylerd` tiles your windows as soon as it has permission.** Quitting it with SIGINT/SIGTERM (Ctrl-C) puts every window it moved back where it was, parked ones included. A crash or `kill -9` does not, and leaves windows of other workspaces parked at the edge of the display; the next `tyler start` tiles them again. Run `tyler tiling off` first if you want windows left alone.
- **Use `main`, not `master`, in Swift identifiers.** SwiftLint's `inclusive_language` rule rejects `master`. The CLI and wire format still say `master` (`ListTarget.main = "master"`).
- macOS has no `timeout`. To bound a command that might hang, use `perl -e 'alarm N; exec @ARGV' <command>`.
- **SwiftLint needs `TOOLCHAIN_DIR`.** Without full Xcode, plain `swiftlint` crashes looking for sourcekitd. Setting `TOOLCHAIN_DIR=/Library/Developer/CommandLineTools` fixes it (the pre-commit hook does this). `.swiftlint.yml` aligns SwiftLint with swift-format (trailing commas; `closure_parameter_position` is off because swift-format moves closure parameters to the next line when only the brace fits) and allows the short names `fd`, `id`, `ok` and `on`.
- **Where swift-format and SwiftLint still disagree, write around it.** A one-element array literal whose element spans lines: SwiftLint wants a trailing comma, swift-format removes it (use a variadic parameter, or put the element on one line). A signature just over 100 columns: swift-format puts `{` on its own line, SwiftLint's `opening_brace` rejects that (shorten the signature). Also, SwiftLint's complexity limit (10) and 5-parameter limit apply: group parameters into a struct rather than splitting logic arbitrarily.
- **Pre-commit** (`.pre-commit-config.yaml`) is installed in `.git/hooks`. A commit that touches Swift files runs format lint, SwiftLint and the tests, and is blocked if any fail. Don't bypass it with `--no-verify`.

## Design principles

These guide every change: modularity, abstraction, grouping what belongs together, separation of concerns, with code sliced by feature. When a change would break one, restructure instead, or say why not. `devdocs/architecture.md` shows the structure they add up to.

- **Input, intent, update, effects.** Every input (a request, a window event, a gesture, a display change) is turned into an intent in domain words; one controller per feature handles it, updates the model and returns effects; the shell carries them out. A controller decides, it doesn't move windows.
- **Desired state, reconciled.** The model is projected to the frame each window should have, and only what differs from what macOS reports is moved. Echoes of tylerd's own moves are filtered where inputs are interpreted, in one place.

- **Slice by feature.** Code that changes together lives together: a feature's types, its state and its tests sit in one folder (as `Sources/TylerCore/Layouts/Tall/` and its tests do), not spread by kind (all models here, all handlers there).
- **One type per file, named after it**, so the file tree is an index of the types: `DisplayTarget` is in `DisplayTarget.swift`, a feature's extension of it in `DisplayTarget+Feature.swift`. The folder groups a family of types. A private helper type is nested in the type that uses it. Its tests are `DisplayTargetTests.swift` (or `DisplayTargetTests+Aspect.swift`) at the mirrored path in `Tests/`; scenario tests, which drive `WindowManager`, are in TylerScenarioTests instead, named after the behaviour and in the folder of their feature (`Displays/MoveToDisplayScenarios.swift`). SwiftLint (`file_name`, `one_declaration_per_file`) and `devtools/check-test-paths` check this.
- **Every piece of state has one owner.** Mutable state is `private` to the type that owns it. Others change it through that type's methods, which say what they do (`slide(to:)`), never through its fields. "Internal so the extensions can reach it" is a sign the state needs an owner.
- **Separate deciding from doing.** Decisions are pure values in TylerCore (`SlidePlan`, `ScrollPlan`, `Snap`, `PointerCheck`), unit tested without fakes; the server carries them out. One place in the server moves and focuses windows; only TylerPlatform talks to macOS.
- **Dependencies point one way.** `WindowManager` composes the parts and connects them. A part never holds a reference back to `WindowManager` or to a part above it: it is handed the shared model it needs (`inout` to change it) and returns what happened. In TylerCore, a context imports only the contexts below it (windows and displays, then Tiling, then Placement, Motion and the rest; see `devdocs/architecture.md`); an import that would point up means a type is in the wrong place. SwiftLint's custom rules in `.swiftlint.yml` reject the common cases.
- **A new feature is a new type, not another `extension WindowManager`.** It is a controller in its own folder, with its decisions in TylerCore. What stays `extension WindowManager` is the feature's input handling and pacing, never a decision.
- **One name per concept, the one users see.** Code uses the words of `docs/` (a display is a display, not a monitor). Rename when the two drift apart.
- **Name a type after its responsibility, not its technology.** Only the lowest layer, whose responsibility is a technology, is named after it (`AXBridge`, `AXClient`). A port's real implementation is `Mac<Port>`, its fake `Fake<Port>`; the ports live in `TylerServer/Ports/`, and TylerPlatform has a folder per port.
- **Abstractions earn their place.** A protocol needs two real implementations or a test seam. Prefer concrete `final class`es and structs, and keep the hot paths (each frame of a slide or swipe, each pointer move) free of existentials and allocation.

## Coding guidelines

@devdocs/coding-guidelines.md

GCD is a documented exception, limited to `IPCServer` (blocking socket I/O), `tylerd`'s signal sources and `AppWriteQueue` (blocking Accessibility writes, a queue per app); the guidelines explain why. Don't use GCD anywhere else without asking.

## Testing notes

- **Test at the lowest layer where the bug could show** (`devdocs/testing-strategy.md`): a unit test for one decision, a scenario test (`Scenario`) for a behaviour seen from outside the server, real windows only for what macOS decides.
- All tests use Swift Testing (XCTest isn't available without Xcode).
- Don't block in `read()` on Swift concurrency's cooperative pool in tests. A task-group version of the concurrent-clients test failed most runs; plain threads pass. The cause is suspected, not verified.
- A test that writes more than the socket buffer (~8 KB) on the same thread that later reads will deadlock.
- Test socket paths must stay short (macOS limit ~104 bytes), so use `/tmp/tyler-<id>.sock`, not `$TMPDIR`.
- The raw Accessibility and `NSWorkspace` calls can't be unit tested (they need a live GUI and permission), so they sit behind `AXClient` and `WorkspaceClient`, dumb one-to-one seams: test the window system above them against `FakeAXClient` and `FakeWorkspaceClient` (`Tests/TylerPlatformTests/WindowSystem/`), and what macOS itself does with the checklist in `devdocs/testing.md`.
- **New scenario tests start from a `Scenario`** (`Tests/TylerScenarioTests/Scenario.swift`): a context, an input, what the user sees. The older ones, and the server's unit tests that need a manager, build it with `ManagerHarness` (`Tests/TylerTestSupport/`, with the fakes, `settle()` and the list and frame helpers; it is a plain target, so it can't import Testing, and its declarations are `package`). Don't copy setup into a suite. `settle()` must stay `@MainActor`: a nonisolated version yields off the main actor and never lets the manager's event pump run.
- **Check real windows with the `live-check` skill** (`devtools/live-check`): window stacking, the menu bar item, where macOS really puts a window, and a replay of the slide. Use it after changing anything that moves windows, and before ticking an item in `devdocs/testing.md`.

## Working mode

- **Work in small increments.** One self-contained change at a time (a fix, one slice of a feature, a doc update), each building, tested and documented on its own.
- **Refactor behind tests.** Before a refactoring, add tests for any behaviour it touches that the tests don't clearly cover, in a commit of their own, so the refactoring commit changes no test (only setup). Check that each new test can fail: break the guarded code on purpose, see the test fail, and put the code back. `devdocs/REFACTORING.md` is the backlog.
- **Review a feature once it works.** When the last increment of a feature (or a fix that took several) is in, re-read everything it changed (`git diff <before the first increment>..HEAD`) against the design principles below: a decision that ended up in the server instead of TylerCore, the same code written twice, state without one owner, names that no longer fit what a type does, comments the code already says. Do the small finds right away, each as its own refactoring commit behind the tests, and put larger ones in `devdocs/REFACTORING.md`. The feature isn't done until this pass is. Features built one increment at a time drift: each step looks fine alone, and only the whole diff shows what to tidy.
- **One commit per increment**, made as soon as it is done and the checks pass, with a message that says what changed and why. Don't bundle unrelated changes. If the working tree already holds other changes (the user's, or an earlier increment's), keep them out of the commit.
- **Trunk-based: work and commit on `main`**, no pull requests and no long-lived branches, however big the feature: land it increment by increment, each one working on its own. The one exception is keeping two agents apart (see Parallel agents).
- **The pre-commit hook stashes unstaged changes but not untracked files**, so it compiles new files that belong to a later commit. When committing part of the tree, set those aside first with `git stash push -u -- <paths>`.

- **Nothing about anyone's personal setup.** The repository is public. Code, comments, tests, docs, plans and commit messages describe a setup in general terms ("an external display above the built-in one", "the Dock on the left"), never the developer's own: no display models, no machine paths or account names, no tools only one person runs. Never write down what was on screen: window and tab titles, document names, page contents, the windows someone had open (log lines and `tyler window list` output included; the coding guidelines keep titles out of the log for the same reason). App names stay where they explain a behaviour ("Firefox refuses the parking spot"). Give the reason for a decision, not "the user said" or "the user found". Measurements stay, with the setup described generically. No hook checks this: read your diff and commit message for it before committing.

## Parallel agents

Two agents often work in this repository at once (for example one on a feature, one on the refactoring backlog), sharing one machine, one checkout of `main` and one running `tylerd`. What has worked:

- **Claim before starting.** Before working on a `devdocs/REFACTORING.md` item, add it to that file's "In progress" line and commit; remove it when done. Before starting a feature, check that line and `plans/` for overlap, and say which files the two pieces of work share.
- **Only one agent works in the main checkout.** Two agents in one checkout get in each other's way: the pre-commit hook stashes the other agent's unstaged edits while it checks (and a write meanwhile can make the stash pop conflict), it compiles the other agent's untracked files, and edits to the same file get mixed into one commit. So when a second agent starts on code, it works in a short-lived worktree: `git worktree add -b <name> ../tyler-<name> main`. Never switch the shared checkout to another branch: that changes files under the other agent.
- **A worktree is still trunk-based.** Rebase onto `main` before each increment and land each increment on `main` as soon as it passes (see the next point), not at the end of the feature. The branch lives for hours, not days. When the other agent is done, remove the worktree and go back to the main checkout.
- **Landing an increment:** run `make check` on the rebased branch, then `git merge --ff-only <name>` in the main checkout, only while the agent there is idle (it refuses to overwrite uncommitted work, but changes files that agent has open). Then run `make build` in the main checkout: the `tyler` on the PATH is usually that checkout's `.build/debug/tyler`, and the worktree's builds don't update it, so it would lag behind `main`. Don't remove a worktree while its agent may still be running in it. If the running `tylerd` was started from the worktree, `make build` and `tyler restart` from the main checkout first: its binary lives in the worktree. After a merge, the other agent re-reads the files that changed before editing them.
- **Commits that were rebased get new hashes.** After a `git pull --rebase` on `main`, `git branch -d <name>` may say the branch is "not fully merged" although every commit is there. Check with `git diff <name> main` before using `-D`.
- **One `tylerd` at a time.** `tyler restart` starts the `tylerd` next to the `tyler` you run, so a restart from a worktree replaces the shared one (and a restart from `main` replaces the worktree's). An older build can't read a state file that names a newer layout and starts afresh, which can leave windows parked: go back with `tyler stop` from the newer build, then `tyler start` from the older one. The same goes for a newer state file version. Agree before restarting `tylerd` for a live check.

## Agentic engineering

The tyler development team wants to continuously improve the agentic engineering setup,
including harness engineering, guardrails, hooks, and automation.

The goal is maintaining code quality and resilience, and streamlining the workflow.

**Proactively offer tips and best practices.** When you notice a moment where a better harness
would have helped - a hook that would have caught something, a `CLAUDE.md` line that would have
prevented a wrong turn, a task worth splitting across parallel agents, a skill or subagent worth
defining, a plan worth writing first - say so briefly, in-line with the work. Don't wait to be
asked, and don't let it swallow the actual task.

Name the concrete trigger (what went wrong or nearly did) and the specific fix, and offer to
implement it. Not "use a hook", but "that `backend.` import slipped through; a rule would catch it - want me to add it?"

Harness pieces get added one at a time, when the need is felt - never inherited as a wall of config.
