# M8. First alpha release (0.1.0)

Publish tyler on GitHub for others to try. The work left is fixing, testing on real windows and
the release itself; new features wait for 0.2 unless they fix a first impression. The repository
should say clearly what works, what hasn't been checked, and what is known to be broken, and it
should hold nothing left over from development and nothing about the author's own setup.

Gathered 2026-10-12; reviewed 2026-10-14 against the code (what was still open, what had become
settled or stale, what was missing).

## Decisions

| # | Question | Decision |
|---|----------|----------|
| D1 | License | **MIT**: short, permissive, usual for macOS tools (AeroSpace and Amethyst are MIT). |
| D2 | What a release ships | **Source only**, installed with `make install`. Prebuilt binaries need a Developer ID and notarization to get past Gatekeeper, and an unsigned or ad-hoc-signed binary loses its Accessibility grant on every update. Revisit for 0.2 (Homebrew tap). |
| D3 | Version scheme | **SemVer**, starting at `0.1.0` (tag `v0.1.0`). 0.x means the CLI, config and wire format may still change. One constant, `TylerVersion` in `TylerRuntime`, holds it. |
| D4 | Git history | **Squashed.** The history named the developer's display model and described their setup in commit messages and old versions of the devdocs. `main` was squashed into one initial commit before the repository went public (it isn't yet); the full history is kept in a git bundle outside the repository. |
| D5 | `plans/` and `devdocs/` | **Finished plans are deleted** once their lasting decisions are in `devdocs/design.md`. `devdocs/` keeps what a contributor or agent needs now: coding guidelines, design decisions, measured macOS behaviour, the refactoring backlog, the strip notes. |
| D6 | `CLAUDE.md`, `.claude/`, `devtools/` | **Kept**: they are the honest record of how tyler is built, and make sense alongside the "vibe-coded" note, without the personal and session-specific parts. |
| D7 | Where open issues live | **`docs/known-issues.md` for the alpha, GitHub issues once public**: one per item of `devdocs/known-issues.md`, labelled `bug`, `limitation`, `unchecked`, `strip`. The markdown lists then shrink to links. |
| D8 | Starting at login | **Out of scope for 0.1.0** (see Out of scope). The README shows `tyler start` from a terminal or a login item. |

## Done

- **Cleanup (phase 1):** the original design chat and `ROADMAP.md` replaced by `devdocs/design.md`,
  `macos-behaviour.md`, `testing.md` and `known-issues.md`; finished plans deleted; `CLAUDE.md`
  shortened; stale mentions and the personal setup removed (the rule is in `CLAUDE.md`, "Nothing
  about anyone's personal setup"); the history squashed (D4).
- **Bugs:** `tiling on` before permission, commands reporting success when focusing failed, a failed
  placement hiding the reply's summary, windows left parked by a crash.
- **Review and profile:** a code review of `MacWindowSystem`, the AX timeout and the state hand-over (10
  findings, the risky ones fixed, the rest filed); a slide and a swipe profiled with a slow app,
  and sped up (one cost line per slide, swipe and drag; writes to each app on a queue of its own).
- **A hung app** (2026-10-14): after a call to an app times out, its windows aren't moved or
  focused for 5 s (`UnresponsiveApps`); checked with `kill -STOP` (a switch waits 1 s once, then
  0.05 s). Running the mouse button interceptor off the main thread moved out of the alpha (see
  Out of scope).
- **Features (phase 3):** `[layouts]` in the config (the default cycle is now tall, grid, full;
  the strip stays out while it is experimental), the version (`tyler --version`, the warning in
  `tyler status`), the sample config `docs/tyler.toml` with a test that it names every key, the
  commands grouped by noun (`tyler window focus next`), `window float on|off`, and
  `tyler config edit` (2026-10-14).
- **Documentation (phase 4):** README, the manual split into `manual.md`, `layouts.md` and
  `features.md`, `keybindings.md`, `troubleshooting.md`, `known-issues.md` for users,
  `CHANGELOG.md`, `LICENSE`, `CONTRIBUTING.md`.
- **Requirements:** the README says "macOS 14 or later. Only macOS 26 on an Apple silicon Mac has
  been tried so far", which covers the untested macOS 14–15 and Intel Macs.

## To do

### Bugs that cost a first impression

Each with a regression test (`devdocs/known-issues.md` has the details).

- [x] **A restart keeps the saved state of apps that attach late.** `restorePending` applies the
  hand-over only to the windows of the first snapshot, so a window of an app that answers a moment
  later comes back as new, on the current workspace. After a restart while the screen is locked,
  every window loses its workspace. Keep the unmatched part of the saved state and apply it as
  windows appear.
  Done (2026-10-14): `LateHandOver`; the state file names each window's process ID, so another
  app's window that takes a handed-over ID starts afresh. Checked with an app that answers late;
  the locked screen is still to check (`devdocs/testing.md`).
- [x] **TextEdit's untitled documents are read as `dialog`** and stay untiled: 3 out of 3 on
  2026-10-14 (AppleScript's `make new document`), while a document opened from a file was tiled.
  A stock app is what someone tries first. Find out what `WindowKind.classify` sees (role,
  subrole) and whether it changes after the window opens.
  Done: macOS reports them as `AXDialog` until TextEdit is first active, and its Open panel as
  `AXStandardWindow` (which tylerd tiled). `classify` now also reads the title bar's buttons;
  checked on real windows.

### Structure

- [ ] **One connection per app** (`plans/app-connection.md`): the platform's window code in layers
  (all apps, one app, the raw calls), and the ports named after what they are: `WindowSystem`
  and its real `MacWindowSystem` (ex `AXBackend`), `Mac…` for every real implementation, the
  protocols in `TylerServer/Ports/`. No change in behaviour; it is the code a reader of the repository would struggle with most, and it makes the
  attach and timeout logic unit-testable. Before the release checks, so they run on the new code.

### Checks on real windows

- [ ] The **release** items of `devdocs/testing.md` (10 open), including the fresh clone on a
  second user account: install the Command Line Tools only, follow the README word for word,
  grant Accessibility, start, bind keys, stop, and fix every step that needs knowledge the README
  doesn't give.
- [ ] README: a demo video of the tiling, the slides and the mouse (`plans/demo-video.md`).

The three test layers (`plans/testing.md`) are under way alongside: the unit and scenario layers
and the `Scenario` setup are in place, the suites move onto it as changes touch them. Its next
step rewrites `devdocs/testing.md` as a catalogue and makes a passing run of it the release
check above; until then the release check is the **release** items as they are.

### Release

- [ ] A last sweep for anything about the personal setup: the tree and every commit message since
  the squash (agents wrote them, and no hook checks it).
- [ ] `CHANGELOG.md` dated, `make check` passes.
- [ ] Make the GitHub repository public; description, topics (`macos`, `window-manager`,
  `tiling`, `swift`), issues on, a bug report template asking for the macOS version, the
  displays, `tyler status` and the log.
- [ ] Tag `v0.1.0`, and a GitHub release with the changelog entry and the status warning.
- [ ] File the items of `devdocs/known-issues.md` and `strip-layout.md` as GitHub issues (D7).

## Out of scope

Not part of 0.1.0; the release says so rather than half-doing them.

- **Starting at login** (`tyler service install`, a LaunchAgent). It needs a stable code
  signature for the Accessibility grant (D8).
- **A Homebrew package** (a tap or a formula). 0.1.0 ships as source (D2).
- **Running the mouse button interceptor off the main thread** (`devdocs/REFACTORING.md`). While
  tylerd's main thread is busy, every click on the system waits for it. Skipping an app that timed
  out took away the long stalls; what is left (slow apps that still answer, reads) is to be
  measured before it is built.
- **A minimized window that keeps its slot** (seen once). A dropped update is logged now, and
  `tyler debug windows` shows the drift; re-reading every tiled window at each sync costs AX calls
  on a busy path, so it waits until the drift is seen again. It stays in `known-issues.md`.
- **Reading a busy app's windows again** (`devdocs/known-issues.md`). The read can only fail
  right after the app answered every call of the attach, so it is rare, nobody has seen it, and
  a window it misses is picked up once it gets focus.
- **Floated windows staying visible under focus follows mouse**
  (`plans/floated-windows-stay-visible.md`): its own plan, after the release.
- **Full Xcode instead of the Command Line Tools.** It only concerns contributors: `make install`
  works with either, and the Makefile's flags for the Command Line Tools are harmless with Xcode;
  `make lint` sets `TOOLCHAIN_DIR` to the Command Line Tools unless it is set already.

## Where the open cases are

- `devdocs/testing.md`: every check against real windows, done or not; the **release** ones must
  pass before the release.
- `devdocs/known-issues.md`: bugs, limitations and what isn't built.
- `devdocs/strip-layout.md`: the strip's own known issues and open questions.
