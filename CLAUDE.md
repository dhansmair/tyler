# tyler

A personal window manager for macOS, written in Swift. It replaces AeroSpace and Amethyst for one specific workflow:

- **xmonad-style tiling.** Each workspace is an ordered *list* of windows with a clear prev/next and a master (the first window). Typical use is two windows side by side, or one on the left and two stacked on the right. New layouts must be easy to add.
- **Workspaces stacked vertically**, like pages. You scroll up and down between them, and the view snaps to one. Each physical display has its own stack.
- **Server plus CLI.** `tylerd` runs in the background and owns all window state. `tyler` is a small client that sends one command and prints the reply. Hotkeys are not built in: bind keys to `tyler` commands with skhd, Karabiner or Raycast.

Windows are controlled through the macOS Accessibility API (no SIP changes). Workspaces work by parking the windows of inactive workspaces in a display corner.

**Terms:** a *display* is a physical screen; a *workspace* is one page of a display's vertical stack (it was called a "virtual monitor" until M4). Don't use "monitor" in code or docs. `docs/manual.md` (Concepts) defines the user-facing terms.

## Status

M1 (IPC, `tyler ping`, test harness) is done. M2 (`tyler list`, window discovery through the Accessibility API) is built and unit tested, and the user has run it against real windows: the `min`, `full` and `focused` flags and removal on close work. The remaining checklist items in the roadmap (new windows, move/resize, app quit, dialogs, second display) are unconfirmed. M3 (tiling on one display: `focus`, `swap`, `layout`, `ratio`, `float toggle`, `tiling`, `retile`) is built and unit tested, but **the code that moves and focuses windows has never run against a real window**: see the checklist in the roadmap. M4 (four workspaces on the primary display: `workspace up|down|<n>` with a slide, `move-to-workspace [--follow]`, restore on exit) is built and unit tested but has not run against real windows either. **`devdocs/ROADMAP.md` is the working document**: read it first, and update it as work progresses (tick off items, log decisions, record open items). `devdocs/notes.md` holds the original design discussion. `docs/` is for users: `docs/manual.md` is the user manual (concepts and the command-line reference); keep it in step when commands change. `plans/` holds the implementation plan for each milestone (`m3-tiling-on-one-display.md`, `m4-virtual-monitors.md`): keep new plans there, not in `~/.claude`.

## Layout

```
Sources/
  TylerCore/     pure logic and POSIX helpers: wire protocol, paths, Unix sockets, window and display types, layouts, Workspace (the ordered tiling list), WorkspaceStack, Parking, animation tracks
  TylerServer/   server logic: CommandRouter, IPCServer, WindowManager (tiling; workspaces in WindowManager+Workspaces), Animator, WindowRegistry, backend protocols
  TylerPlatform/ real macOS code (AX, NSWorkspace, NSScreen); not unit tested, keep it thin
  TylerClient/   argv parsing, response formatting, IPC client
  tylerd/        server executable (thin)
  tyler/         CLI executable (thin)
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
- **Run the pieces by hand:** `.build/debug/tylerd` in one terminal, `.build/debug/tyler ping` or `tyler list` in another. Set `TYLER_SOCKET=/tmp/x.sock` to use a different socket (default `~/.tyler/tyler.sock`).
- **`tyler list` and the tiling commands need Accessibility permission.** Grant it in System Settings > Privacy & Security > Accessibility to the terminal app that runs `tylerd`. Without it, `tylerd` still runs and they print instructions.
- **`tylerd` tiles your windows as soon as it has permission.** Quitting it with SIGINT/SIGTERM (Ctrl-C) puts every window it moved back where it was, parked ones included. A crash or `kill -9` does not, and leaves windows of other workspaces parked in the bottom-right corner. Run `tyler tiling off` first if you want windows left alone.
- **Use `main`, not `master`, in Swift identifiers.** SwiftLint's `inclusive_language` rule rejects `master`. The CLI and wire format still say `master` (`ListTarget.main = "master"`).
- macOS has no `timeout`. To bound a command that might hang, use `perl -e 'alarm N; exec @ARGV' <command>`.
- **SwiftLint needs `TOOLCHAIN_DIR`.** Without full Xcode, plain `swiftlint` crashes looking for sourcekitd. Setting `TOOLCHAIN_DIR=/Library/Developer/CommandLineTools` fixes it (the pre-commit hook does this). `.swiftlint.yml` aligns SwiftLint with swift-format (trailing commas) and allows the short names `fd`, `id`, `ok`, `on` and `up`.
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
