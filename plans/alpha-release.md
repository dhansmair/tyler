# M8. First alpha release (0.1.0)

Publish tyler on GitHub for others to try. No new features beyond the ones listed under phase 3:
the work is testing, fixing, documentation and cleaning up the repository. The repository should
say clearly what works, what hasn't been checked, and what is known to be broken, and it should
hold nothing left over from development and nothing about the author's own setup.

Gathered 2026-10-12 from the maintainer's list, `devdocs/ROADMAP.md`, `devdocs/REFACTORING.md`,
`devdocs/strip-layout.md` and a look through the tree.

## Decisions to make first

| # | Question | Recommendation |
|---|----------|----------------|
| D1 | License | **Decided: MIT.** MIT: short, permissive, usual for macOS tools (AeroSpace is MIT, Amethyst MIT). GPL-3.0 if derivatives must stay open. |
| D2 | What a release ships | **Decided: source only.** Source only, installed with `make install`. Prebuilt binaries need a Developer ID and notarization to get past Gatekeeper, and an unsigned or ad-hoc-signed binary loses its Accessibility grant on every update. Revisit for 0.2 (Homebrew tap). |
| D3 | Version scheme | **Decided: SemVer.** SemVer, starting at `0.1.0` (tag `v0.1.0`). 0.x means the CLI, config and wire format may still change. One constant, `TylerVersion` in `TylerRuntime`, holds it. |
| D4 | Git history | **Decided: squashed.** The history named the developer's display model and described their setup in about 20 commit messages and in old versions of the devdocs. `main` was squashed into one initial commit before the repository went public (it wasn't yet); the full history is kept in a git bundle outside the repository. |
| D5 | What happens to `plans/` and `devdocs/` | Finished plans are history: delete them (git keeps them; with D4's squash, the private backup does). Keep `devdocs/` for what a contributor or agent needs now: coding guidelines, design decisions, measured macOS behaviour, the refactoring backlog, the strip notes. |
| D6 | `CLAUDE.md`, `.claude/`, `devtools/` | Keep: they are the honest record of how tyler is built, and make sense alongside the "vibe-coded" note. Strip the personal and session-specific parts (see phase 4). |
| D7 | Where open issues live after the release | **Decided: `docs/known-issues.md` for the alpha, GitHub issues once public.** GitHub issues, one per item in `devdocs/known-issues.md`, labelled `bug`, `limitation`, `unchecked`, `strip`. The markdown lists in the repo then shrink to links. |
| D8 | Starting at login | **Decided: out of scope for 0.1.0** (see Out of scope). `service install` (a LaunchAgent) isn't built, and it needs a stable code signature. For the alpha, document `tyler start` from a terminal (or a login item that runs it), and say that a LaunchAgent comes later. |

## Phase 1. Repository cleanup

- [x] Delete `devdocs/notes.md` (the original design chat).
- [x] Replace `devdocs/ROADMAP.md` (470 lines) with:
  - `devdocs/design.md`: the decisions that still hold (list model, parking edges, horizontal slide, no-crossing rule, IPC, restart hand-over, config rules, terminology), with the reason for each, in a few lines each.
  - `devdocs/macos-behaviour.md`: what was measured about macOS (where it clamps windows, the visible frame's 1-point rule, the 30-point strip on a display without the menu bar, display change bursts, gesture and move taps, the Dock's full-display window, active tap timeouts). Valuable and hard to rediscover; written without naming the author's hardware ("an external display above the built-in one", never a display model).
  - `devdocs/testing.md`: the manual test checklist, used before every release.
  - `devdocs/known-issues.md`: bugs, limitations and what isn't built (until they become GitHub issues, D7).
  - The milestone log, the per-increment checklists and the session notes go (git keeps them).
- [x] Delete the finished plans in `plans/` (D5). Keep `plans/` for upcoming work, starting with this file.
- [x] Shorten the status paragraph in `CLAUDE.md` to two or three sentences pointing at the new files, and fix every pointer to `ROADMAP.md` (`CLAUDE.md`, `.claude/skills/live-check/SKILL.md`, `REFACTORING.md`).
- [x] `CLAUDE.md`: drop milestone history. The Parallel agents section stays (two agents still work side by side).
- [x] `.vscode/` into `.gitignore`.
- [x] Remove stale mentions: "Customizable keybindings" in the README (tyler has none). The `wide` layout, `service install` in the CLI target and "Not in the manual until the swipe works" went with the roadmap.
- [x] Remove anything about the personal setup (see the next section).
- [x] D4: squash the history into one commit.

### Personal setup

Done in the working tree: the developer's display model is gone from tests, docs and the live-check
skill (tests say "external display"; "laptop" stays, as the generic built-in display), and
decisions give their reason instead of who made them. Measurements keep their macOS version. App
names (Firefox, Ghostty) stay where they explain a behaviour. The rule is in `CLAUDE.md`
("Nothing about anyone's personal setup"); no hook checks it.

The git history, whose old commit messages and old versions of the deleted docs named the display
and described the setup, was squashed (D4).

## Phase 2. Stabilise

### A hung app must not freeze tyler

One app that stops answering can stall all of `tylerd`, and with it every click in every app.

- [ ] **Skip an app that doesn't answer for a few seconds** (`devdocs/REFACTORING.md`). Nothing
  remembers that an app timed out. The steps of a slide no longer wait for it (each app is written
  on its own queue, `AppWriteQueue`), but the final placement of every switch and every later
  command still wait the full 1 s Accessibility timeout for it again.
- [ ] **Run the mouse button interceptor off the main thread** (`devdocs/REFACTORING.md`). It is
  an active event tap on every mouse down, drag and up, and its callback runs on tylerd's main
  thread: a stall there holds every click on the system for up to about 1 s.

### No lost windows

Each of these can leave a window untracked or on the wrong workspace (`devdocs/known-issues.md`).

- [ ] **A restart keeps the saved state of apps that attach late.** The handover is applied only
  to the windows in the first snapshot, so a window of an app that answers a moment later comes
  back as new. After a restart while the screen is locked, every window loses its workspace.
  Keep the unmatched part of the saved state and apply it as windows appear.
- [ ] **Windows of a busy app are read again.** A failed or timed-out windows read looks like an
  app without windows, and nothing reads them again. Retry the read when it fails.
- [ ] **A minimized window leaves the layout.** One stayed tiled and held an empty slot. Log a
  dropped update, and re-read whether tiled windows are minimized when a sync runs.

### Bugs to fix (each with a regression test)

- [x] `tyler tiling on` answers "tiling on" while tylerd still waits for Accessibility permission (`setTiling` skips `beginCommand`). Done: the mode is recorded and the reply says it waits for permission.
- [x] `workspace` and `move-to-workspace` report success when focusing failed (`focusCurrentWorkspace` only logs).
- [x] A failed placement drops the success text ("workspace 3" disappears) in `setLayout` and the workspace commands, while `reload` appends the failures. Pick one way. Done: every command answers like `reload`, its summary then `; ` and what went wrong.
- [x] After a crash or `kill -9`, windows stay parked at the edge. At least check what the next `tyler start` does with them; if it doesn't bring them back, add a `tyler rescue` or have tylerd unpark windows found at a parking spot. Others will hit this, and a "lost" window is the worst first impression.
  Done: a fresh tylerd already tiled them, but remembered the parking spot as their original frame, so `stop` sent them back there; it now remembers them pulled into view. Still to check on real windows (`devdocs/testing.md`).

### Refactoring and performance

`devdocs/REFACTORING.md` holds no item a release item needs. Before the release:

- [x] A fresh review of the code most likely to fail for other people: `AXBackend` (app attach retries, 6 × 500 ms, are guesses), the 1 s AX timeout blocking the main actor during slides and the active tap, the state file hand-over. Use `/code-review high` on those files, file what it finds in `REFACTORING.md`, fix only what is risky.
  Done: 10 findings. Fixed: a left-behind state file applied after a reboot, the 1 s AX timeout missing on window elements (they waited ~6 s), apps never attached after their retries ran out, a closed window kept as an empty slot when its destroyed notification never came. Filed: three items in `REFACTORING.md` (the active tap on the main thread, skipping a hung app, cheaper moved reads), three bugs in `known-issues.md`.
- [x] Profile one slide and one swipe with a slow app (Firefox) on screen; record the numbers in `devdocs/macos-behaviour.md`.
  Done, with the speed-ups the numbers called for: one log line per slide, swipe and drag with
  what it cost; only the frame read on moved and resized notifications; writes to each app on a
  queue of its own (`AppWriteQueue`). What tylerd does and the numbers are in `docs/features.md`
  (Performance).

### Testing on a clean setup

- [ ] Fresh clone on a second user account: install the Command Line Tools only, follow the README word for word, grant Accessibility, start, bind keys, stop. Fix every step that needs knowledge the README doesn't give.
- [ ] Oldest supported macOS: `Package.swift` says 14; it has only run on 26.7. Either test on 14/15 or raise the minimum to what was tested and say so.
- [ ] Intel Macs: untested (built on arm64). Say so.
- [ ] Full Xcode installed instead of the Command Line Tools: check `make test` and `make lint` (the Makefile passes CLT-specific flags).
- [ ] Run the **release** items of `devdocs/testing.md`.

## Phase 3. Small features for the release

- [x] **`[layouts]` in the config.** `cycle = ["tall", "full"]` limits `layout next` (and the menu) to those layouts, in that order; `default = "tall"` is the layout of a new workspace. The strip is left out of the default cycle while it is experimental (decided: yes, for 0.1.0). Unit tested; manual and sample config updated.
- [x] **Version.** One constant in `TylerCore`; `tyler --version` prints `tyler 0.1.0`; `tyler status` shows tylerd's version and warns when it differs from the client's (`ServerStatus` gets an optional field). A test that the constant matches `CHANGELOG.md`'s latest entry.
- [x] **Sample config** `docs/tyler.toml`: every setting with its default and a one-line comment. A test parses it and checks that it names every key `Config` accepts, so it can't drift (the manual's Configuration section can then shrink to pointing at it). Done: every active line is a default (the test expects `Config()`), the tables of apps and displays are commented examples; the manual keeps its table of settings as the reference and links the sample.

- [x] **Commands grouped by what they act on** (`tyler <noun> <verb>`), before 0.1.0 while
  breaking the CLI costs nothing. The first word is the thing that changes: `window`, `workspace`,
  `layout`, `display`; tylerd's own commands and `tiling` stay at the top. No aliases for the old
  names. Only the client's parser changes; the wire format stays.

  | New | Old |
  | --- | --- |
  | `window list [--json]` | `list` |
  | `window focus next\|prev\|master` | `focus` |
  | `window swap next\|prev\|master` | `swap` |
  | `window float on\|off\|toggle` | `float toggle` |
  | `window size half\|full\|quarter\|next` | `size` |
  | `window move-to-workspace prev\|next\|<n> [--follow]` | `move-to-workspace` |
  | `window move-to-display prev\|next\|<n> [--follow]` | `move-to-display` |
  | `workspace focus prev\|next\|<n>` | `workspace <target>` |
  | `workspace move-to-display prev\|next\|<n>` | `move-workspace-to-display` |
  | `workspace retile` | `retile` |
  | `layout set tall\|full\|strip` | `layout tall` |
  | `layout next` | `layout next` |
  | `layout ratio +<step>\|-<step>` | `ratio` |
  | `display focus prev\|next\|<n>` | `display <target>` |

  Done: the parser with its tests, the manual and every doc, devtool and skill that names a command
  (one commit, since a test ties the manual to the parser), then `window float on|off` (a
  `float(FloatMode)` request replaces `toggleFloat`). No changelog table from old to new: 0.1.0 is
  the first release.

## Phase 4. Documentation

- [x] **README**: what tyler is, the alpha and "vibe-coded" warning with the way back (`tiling off`, `stop`), features (strip experimental, no SIP changes), requirements, install from source, updating, starting at login from the shell (D8), uninstalling, keybindings, a short config, links.
- [ ] README: a GIF or screenshot of a slide and the map (needs a screen recording by the maintainer).
- [x] README and manual: link the sample config `docs/tyler.toml` once it lands (phase 3).
- [x] **Manual split:** `docs/manual.md` (Concepts back to the entities, running tylerd, configuration, commands), `docs/layouts.md` (strip marked experimental, with what it doesn't handle), `docs/features.md`.
- [x] `docs/keybindings.md`: a suggested set, for skhd, Karabiner-Elements and Raycast.
- [x] `docs/troubleshooting.md`.
- [x] `docs/known-issues.md` for users (D7), kept in step with `devdocs/known-issues.md`.
- [x] `CHANGELOG.md` with a `0.1.0 (unreleased)` entry.
- [x] `LICENSE` (MIT).
- [x] `CONTRIBUTING.md`.

## Phase 5. Release

- [ ] Version 0.1.0 set, `CHANGELOG.md` dated, `make check` passes.
- [ ] Tag `v0.1.0`, GitHub release with the changelog entry and the status warning.
- [ ] GitHub repository: description, topics (`macos`, `window-manager`, `tiling`, `swift`), issues on, a bug report template asking for macOS version, displays, `tyler status` and the log.
- [ ] File the items of `devdocs/known-issues.md` and `strip-layout.md` as GitHub issues (D7).

## Out of scope

Not part of 0.1.0; the release says so rather than half-doing them.

- **Starting at login** (`tyler service install`, a LaunchAgent). It needs a stable code
  signature for the Accessibility grant. The README shows how to run `tyler start` from a login
  item instead (D8).
- **A Homebrew package** (a tap or a formula). 0.1.0 ships as source, installed with
  `make install` (D2).

## Unchecked cases and open issues

Gathered from the roadmap when it was split (phase 1):
- `devdocs/testing.md`: every check against real windows, done or not. The ones marked **release**
  must pass before the release.
- `devdocs/known-issues.md`: bugs, limitations and what isn't built.
- `devdocs/strip-layout.md`: the strip's own known issues and open questions.

## Order of work

1. Decisions D1–D8 with the maintainer.
2. Phase 1 (cleanup) first, so every later doc change lands in the new structure.
3. Phase 2 bugs and the must-check cases, interleaved with phase 3.
4. Phase 4 docs, then the clean-setup test from phase 2 against the finished README.
5. Phase 5.

Phases 1 and 4 touch only docs and phases 2 and 3 mostly code, so two agents can run them side by side (the Parallel agents rules apply; they share `CLAUDE.md` and `docs/manual.md`).
