# mwm

A personal window manager for macOS, written in Swift. It replaces AeroSpace and Amethyst for one specific workflow:

- **xmonad-style tiling.** Each workspace is an ordered *list* of windows with a clear prev/next and a master (the first window). Typical use is two windows side by side, or one on the left and two stacked on the right. New layouts must be easy to add.
- **Virtual monitors stacked vertically**, like pages. You scroll up and down between them, and the view snaps to one. Each physical display has its own stack.
- **Server plus CLI.** `mwmd` runs in the background and owns all window state. `mwm` is a small client that sends one command and prints the reply. Hotkeys are not built in: bind keys to `mwm` commands with skhd, Karabiner or Raycast.

Windows are controlled through the macOS Accessibility API (no SIP changes). Virtual monitors work by parking the windows of inactive monitors in a display corner.

## Status

Only milestone M1 is done: IPC, `mwm ping` and the test harness. Window handling starts in M2. **`docs/ROADMAP.md` is the working document**: read it first, and update it as work progresses (tick off items, log decisions, record open items). `docs/notes.md` holds the original design discussion.

## Layout

```
Sources/
  MWMCore/     pure logic and POSIX helpers: wire protocol, paths, Unix sockets
  MWMServer/   server logic: CommandRouter, IPCServer
  MWMClient/   argv parsing, response formatting, IPC client
  mwmd/        server executable (thin)
  mwm/         CLI executable (thin)
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
- **Run the pieces by hand:** `.build/debug/mwmd` in one terminal, `.build/debug/mwm ping` in another. Set `MWM_SOCKET=/tmp/x.sock` to use a different socket (default `~/.mwm/mwm.sock`).
- macOS has no `timeout`. To bound a command that might hang, use `perl -e 'alarm N; exec @ARGV' <command>`.
- **SwiftLint needs `TOOLCHAIN_DIR`.** Without full Xcode, plain `swiftlint` crashes looking for sourcekitd. Setting `TOOLCHAIN_DIR=/Library/Developer/CommandLineTools` fixes it (the pre-commit hook does this). `.swiftlint.yml` aligns SwiftLint with swift-format (trailing commas) and allows `fd`.
- **Pre-commit** (`.pre-commit-config.yaml`) is installed in `.git/hooks`. A commit that touches Swift files runs format lint, SwiftLint and the tests, and is blocked if any fail. Don't bypass it with `--no-verify`.

## Coding guidelines

@docs/coding-guidelines.md

Known conflict: the guidelines say not to use new GCD APIs, but `IPCServer` and `mwmd` use `Thread`, `DispatchQueue`, `DispatchSemaphore` and `DispatchSource` for blocking socket I/O and signals. This is logged as an open item in the roadmap. Don't spread GCD further without asking.

## Testing notes

- All tests use Swift Testing (XCTest isn't available without Xcode).
- Don't block in `read()` on Swift concurrency's cooperative pool in tests. A task-group version of the concurrent-clients test failed most runs; plain threads pass. The cause is suspected, not verified.
- A test that writes more than the socket buffer (~8 KB) on the same thread that later reads will deadlock.
- Test socket paths must stay short (macOS limit ~104 bytes), so use `/tmp/mwm-<id>.sock`, not `$TMPDIR`.
- The AX layer can't be unit tested (it needs a live GUI and permission). Keep it thin and cover it with the manual checklist in the roadmap.
