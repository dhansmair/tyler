# tyler

A personal window manager for macOS, written in Swift. It replaces AeroSpace and Amethyst for one specific workflow:

- **xmonad-style tiling.** Each workspace is an ordered *list* of windows with a clear prev/next and a master (the first window). Typical use is two windows side by side, or one on the left and two stacked on the right. New layouts must be easy to add.
- **Workspaces side by side in a row**, like pages. You move left and right between them, and the view snaps to one. Each physical display has its own row.
- **Server plus CLI.** `tylerd` runs in the background and owns all window state. `tyler` is a small client that sends one command and prints the reply. Hotkeys are not built in: bind keys to `tyler` commands with skhd, Karabiner or Raycast.

Windows are controlled through the macOS Accessibility API (no SIP changes). Workspaces work by parking the windows of inactive workspaces just past the display's right edge, and switching slides horizontally: macOS won't let a window leave through the top or bottom of the screen (measured; see `Parking` and the M4 notes in the roadmap).

**Terms:** a *display* is a physical screen; a *workspace* is one page of a display's row of workspaces (it was called a "virtual monitor" until M4). Don't use "monitor" in code or docs. `docs/manual.md` (Concepts) defines the user-facing terms.

## Status

**Keep this status line current.** Whenever a feature is complete or its state changes (built, unit tested, checked against real windows, dropped), update the paragraph below in the same commit, so it never contradicts the roadmap.

M1 (IPC, `tyler ping`, test harness) is done. M2 (`tyler list`, window discovery through the Accessibility API) is built and unit tested, and the user has run it against real windows: the `min`, `full` and `focused` flags and removal on close work. The remaining checklist items in the roadmap (new windows, move/resize, app quit, dialogs, second display) are unconfirmed. M3 (tiling on one display: `focus`, `swap`, `layout`, `ratio`, `float toggle`, `tiling`, `retile`) is built and unit tested, but **the code that moves and focuses windows has never run against a real window**: see the checklist in the roadmap. M4 (four workspaces on the primary display: `workspace prev|next|<n>` with a slide, `move-to-workspace [--follow]`, restore on exit) is built and unit tested but has not run against real windows either. M6 has started: `~/.config/tyler/tyler.toml` with `[gaps]` and `tyler reload` are built, unit tested and checked against real windows; `[workspaces] count` and `[assign]` (app to workspace) are built and unit tested, not yet run against real windows. Mouse resizing (in `tall`, the layout follows a dragged edge between windows; plan in `plans/mouse-resize.md`) and swap by drag and drop (drag a tiled window by its title bar onto another and the two swap, with a live preview; plan in `plans/swap-by-drag.md`) are built, unit tested and checked against real windows by the user. Swiping between workspaces (M7: a 3-finger trackpad swipe, the windows following the fingers; plan in `plans/trackpad-swipe.md`) is built, unit tested and checked against real windows by the user; wrap-around, the ignored 4-finger and vertical swipes, and slow apps are still unconfirmed. **`devdocs/ROADMAP.md` is the working document**: read it first, and update it as work progresses (tick off items, log decisions, record open items). `devdocs/notes.md` holds the original design discussion. `devdocs/REFACTORING.md` is the ranked refactoring and performance backlog: tick items off there as they are done. `docs/` is for users: `docs/manual.md` is the user manual (concepts and the command-line reference); keep it in step when commands change. `plans/` holds the implementation plan for each milestone (`m3-tiling-on-one-display.md`, `m4-virtual-monitors.md`): keep new plans there, not in `~/.claude`.

## Layout

```
Sources/
  TylerCore/     pure logic and POSIX helpers: wire protocol, paths, Unix sockets, window and display types, layouts, Workspace (the ordered tiling list), WorkspaceStack, WorkspaceSync (which windows each workspace holds), SlidePlan, Parking, animation tracks, IndicatorState (menu bar contents), the trackpad pan (PanRecognizer, OneEuroFilter, Snap), TOML parser and Config
  TylerServer/   server logic: CommandRouter, IPCServer, WindowManager (tiling; per-window state such as floated windows and original frames in WindowBookkeeping; the slide, pan or drag in progress in Interaction; keeping the lists in step with the windows and app assignments in WindowManager+Sync, workspaces in WindowManager+Workspaces, config and reload in WindowManager+Config, menu bar updates in WindowManager+Indicator, mouse resizing and swap by drag in WindowManager+Mouse, trackpad swipes in WindowManager+Pan), PointerInput, Animator, WindowRegistry, backend and Indicator protocols
  TylerPlatform/ real macOS code (AX, NSWorkspace, NSScreen, the NSStatusItem, the mouse button monitor, the trackpad's gesture tap in SwipeTap); not unit tested, keep it thin
  TylerClient/   argv parsing, response formatting, IPC client
  tylerd/        server executable (thin)
  tyler/         CLI executable (thin)
devtools/      live-check: checks against real windows (see .claude/skills/live-check)
Tests/         one test target per library
```

Keep the executables thin. Logic goes in the libraries, and anything that touches macOS (AX, NSScreen, timers) goes behind a protocol so tests can use fakes.

## Commands

```bash
make build     # swift build
make test      # swift test with the flags below; use this, not plain `swift test`
make install   # release build, copied to ~/.local/bin (SIGN_ID=<identity> to codesign)
swift format lint --recursive --strict Sources Tests Package.swift
TOOLCHAIN_DIR=/Library/Developer/CommandLineTools swiftlint --strict
pre-commit run --all-files   # runs swift format lint, swiftlint and make test
```

- **Use `make test`.** The Command Line Tools ship Swift Testing, but SwiftPM doesn't find it without extra framework and rpath flags. The Makefile passes them.
- **Run the pieces by hand:** `.build/debug/tyler start` (background, log in `~/.tyler/tyler.log`) or `.build/debug/tylerd` in a terminal, then `.build/debug/tyler ping` or `tyler list`. After `make build`, run `tyler restart`: a running `tylerd` keeps the old code, and `tyler status` warns about it. Restart keeps every window where it is (the old tylerd hands its workspaces over through `~/.tyler/tyler.state.json`); `stop` puts windows back. Set `TYLER_SOCKET=/tmp/x.sock` to use a different socket (default `~/.tyler/tyler.sock`).
- **`tyler list` and the tiling commands need Accessibility permission.** Grant it in System Settings > Privacy & Security > Accessibility to the terminal app that runs `tylerd`. Without it, `tylerd` still runs and they print instructions.
- **`tylerd` tiles your windows as soon as it has permission.** Quitting it with SIGINT/SIGTERM (Ctrl-C) puts every window it moved back where it was, parked ones included. A crash or `kill -9` does not, and leaves windows of other workspaces parked at the right edge of the display. Run `tyler tiling off` first if you want windows left alone.
- **Use `main`, not `master`, in Swift identifiers.** SwiftLint's `inclusive_language` rule rejects `master`. The CLI and wire format still say `master` (`ListTarget.main = "master"`).
- macOS has no `timeout`. To bound a command that might hang, use `perl -e 'alarm N; exec @ARGV' <command>`.
- **SwiftLint needs `TOOLCHAIN_DIR`.** Without full Xcode, plain `swiftlint` crashes looking for sourcekitd. Setting `TOOLCHAIN_DIR=/Library/Developer/CommandLineTools` fixes it (the pre-commit hook does this). `.swiftlint.yml` aligns SwiftLint with swift-format (trailing commas; `closure_parameter_position` is off because swift-format moves closure parameters to the next line when only the brace fits) and allows the short names `fd`, `id`, `ok` and `on`.
- **Where swift-format and SwiftLint still disagree, write around it.** A one-element array literal whose element spans lines: SwiftLint wants a trailing comma, swift-format removes it (use a variadic parameter, or put the element on one line). A signature just over 100 columns: swift-format puts `{` on its own line, SwiftLint's `opening_brace` rejects that (shorten the signature). Also, SwiftLint's complexity limit (10) and 5-parameter limit apply: group parameters into a struct rather than splitting logic arbitrarily.
- **Pre-commit** (`.pre-commit-config.yaml`) is installed in `.git/hooks`. A commit that touches Swift files runs format lint, SwiftLint and the tests, and is blocked if any fail. Don't bypass it with `--no-verify`.

## Coding guidelines

@devdocs/coding-guidelines.md

GCD is a documented exception, limited to `IPCServer` (blocking socket I/O) and `tylerd`'s signal sources; the guidelines explain why. Don't use GCD anywhere else without asking.

## Testing notes

- All tests use Swift Testing (XCTest isn't available without Xcode).
- Don't block in `read()` on Swift concurrency's cooperative pool in tests. A task-group version of the concurrent-clients test failed most runs; plain threads pass. The cause is suspected, not verified.
- A test that writes more than the socket buffer (~8 KB) on the same thread that later reads will deadlock.
- Test socket paths must stay short (macOS limit ~104 bytes), so use `/tmp/tyler-<id>.sock`, not `$TMPDIR`.
- The AX layer can't be unit tested (it needs a live GUI and permission). Keep it thin and cover it with the manual checklist in the roadmap.
- **Server tests build their manager with `ManagerHarness`** (`Tests/TylerServerTests/Harness.swift`), which also holds `settle()` and the list and frame helpers. Don't copy setup into a suite. `settle()` must stay `@MainActor`: a nonisolated version yields off the main actor and never lets the manager's event pump run.
- **Check real windows with the `live-check` skill** (`devtools/live-check`): window stacking, the menu bar item, where macOS really puts a window, and a replay of the slide. Use it after changing anything that moves windows, and before ticking a roadmap checklist item.

## Working mode

- **Work in small increments.** One self-contained change at a time (a fix, one slice of a feature, a doc update), each building, tested and documented on its own.
- **Refactor behind tests.** Before a refactoring, add tests for any behaviour it touches that the tests don't clearly cover, in a commit of their own, so the refactoring commit changes no test (only setup). Check that each new test can fail: break the guarded code on purpose, see the test fail, and put the code back. `devdocs/REFACTORING.md` is the backlog.
- **One commit per increment**, made as soon as it is done and the checks pass, with a message that says what changed and why. Don't bundle unrelated changes. If the working tree already holds other changes (the user's, or an earlier increment's), keep them out of the commit.
- **Commit directly on `main`** for now; no branches or pull requests.
- **The pre-commit hook stashes unstaged changes but not untracked files**, so it compiles new files that belong to a later commit. When committing part of the tree, set those aside first with `git stash push -u -- <paths>`.

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
