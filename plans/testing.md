# Testing in three layers: unit, scenario, end to end

## Context

tyler has about 1,000 tests, and nothing says which kind each one is. About 400 of the ~450 in
TylerServerTests are integration tests: they build a `WindowManager` on fakes through
`ManagerHarness`, feed an event and check the frames. They sit next to the ~30 tests of a single
controller and are named after the controllers too (`DisplayControllerTests+MoveToDisplay.swift`),
with no difference between the two kinds. Each suite writes its own setup: `makeHarness` 6 times,
"run the animations until done" 6 times, and windows reach a workspace through `osFocus` +
`moveToWorkspace` instead of being placed there.

At the top, `devdocs/testing.md` is 80 prose checkboxes. A tick says that something worked once
on some build, which doesn't protect a release from a regression. `devtools/live-check` only
observes: it moves windows over AX but never fakes input, so every swipe, drag and focus follows
mouse check is done by hand.

The aim is a pyramid of three named layers, each with its own place, way of writing a test and
command. The middle layer reads as *context → input → expected frames*. The top is a short
catalogue of scenarios, run in full before every release, automated as far as possible.

## The layers

| Layer | Covers | Where | Run |
|---|---|---|---|
| Unit | A pure decision (TylerCore), one controller on a `Model` and `ControllerContext`, a plain server type (Animator, Debounce, WindowRegistry) | `Tests/<Target>Tests/`, mirroring the sources | `make test-unit`, every commit |
| Scenario | The whole server on fakes: displays, windows and workspaces given; an input; the lists, frames, focus and parking that come out | `Tests/TylerScenarioTests/<Feature>/` | `make test-scenario`, every commit |
| End to end | Real tylerd on real macOS: the AX layer, the event taps, timing, clamping, the menu bar | the catalogue in `devdocs/testing.md`; `devtools/e2e` | before every release, or on demand |

Where a test goes: at the lowest layer where the bug could show. A single decision gets a unit
test. A behaviour `docs/` promises, or a bug in the plumbing between parts, gets a scenario. An
end-to-end scenario exists only for what macOS decides (AX, a tap, timing, the menu bar). If the
reason is only logic, it moves down to a scenario test.

## Scenario tests

A `Scenario` on top of `ManagerHarness`:

```swift
@Test func draggingTheMainWindowOntoTheStackSwapsThem() async {
  let scenario = await Scenario(displays: [.builtIn], workspaces: [[1, 2, 3]], layout: .tall)
  await scenario.drag(1, by: CGVector(dx: 900, dy: 300))
  #expect(scenario.list(1) == [2, 1, 3])
  #expect(scenario.frame(of: 2) == scenario.rect(.leftHalf))
}
```

- **Context.** `Scenario` owns the harness, a `TestClock`, a `FakePointer` and a `FakeStacking`.
  It places windows on workspaces directly (each workspace's list, the current workspace, the
  layout) instead of replaying commands.
- **Inputs in the words of `docs/`:** `drag`, `modifierDrag`, `resize`, `swipe(.left, fingers:)`,
  `command("workspace focus next")` (through the real CLI parser), `open`, `close`, `focus`,
  `plugIn` / `unplug`. Each input runs until things are quiet, animations included, unless the
  test steps frames with `step`.
- **Checks:** what the user sees, read with `list(_:)`, `frame(of:)`, `isParked(_:)`, `shown`,
  `focused` and checked with plain `#expect`, which shows both values when it fails. Frames are
  named regions of the display (`.leftHalf`, `.rightTop`),
  worked out from the display and the gaps in the test support, never by the layout code under
  test. Literal rects where precision is the point (clamping, a resize by a delta). No golden
  files.
- **Names.** `Tests/TylerScenarioTests/<Feature>/<Behaviour>Scenarios.swift`, where `<Feature>`
  is a folder of `Sources/TylerServer/` (`Drag/SwapScenarios.swift`). `devtools/check-test-paths`
  checks that rule for this target instead of the mirror rule.

## End to end

1. **The catalogue.** `devdocs/testing.md` becomes tables grouped by context (layout × number of
   windows × displays). Each row has an id (`TALL-3-SWAP`), the context, the action, the expected
   result, how it runs (`auto` or `manual`), why it is end to end, and the scenario test that
   covers its logic. It has no checkboxes and no dates: it says what to run, not what ran.
2. **A release run.** Each run writes `devdocs/test-runs/<version>.md`: the date, the macOS
   version, the display setup (in general terms), and pass, fail or skipped per id. `devtools/e2e`
   fills in the `auto` rows. `devtools/e2e manual` walks the manual rows one at a time (the action,
   the expected result, then y, n or skip). A failure blocks the release or links a known issue.
   Every manual row costs time on every release, so each one says why it can't be automated, and
   the manual set stays small.
3. **Fixture windows.** A small AppKit app in `devtools/` opens a given number of plainly titled
   windows, so a run starts from a known context and leaves the user's windows alone.
4. **`devtools/e2e`.** It starts tylerd on its own socket, opens the fixtures, and drives them with
   `tyler` commands and CGEvent mouse and modifier input. It checks the result with
   `tyler window list --json`, `tyler debug windows --json` and `live-check stacking`. It moves the
   real pointer, so it checks first that the screen is unlocked, says that a run starts, needs
   hands off the machine while it runs, and puts tylerd and the windows back afterwards.
   Trackpad swipes, plugging displays, the lid and cmd-tab stay manual.

## Steps

Each step is one commit with `make check` green.

- [x] This plan.
- [x] `devdocs/testing-strategy.md`: the layers, where a test goes, the commands. Linked from
  CLAUDE.md (Testing notes, where things are written down) and `devdocs/architecture.md`.
- [x] A test support target holding `ManagerHarness` and the fakes, which both server test targets
  use (a plain target: no Testing import; `make release` builds the products only).
- [x] The `TylerScenarioTests` target; `make test-unit` and `make test-scenario`;
  `check-test-paths` taught the scenario rule.
- [x] `Scenario`, with tests of its own setup and three pilots: a swap by dragging in `tall`, a
  swipe to the next workspace, a window moved to another display. Each pilot is seen to fail with
  the guarded code broken on purpose.
- [x] Move the integration suites into TylerScenarioTests with no assertion changed (1021 tests
  before and after; the pilots joined the suites they overlap with).
- [ ] Rewrite the moved suites on `Scenario`, one suite at a time, when a change touches it. They
  still build `ManagerHarness` themselves, copy helpers (`makeHarness` 6 times, a loop that runs
  the animations 6 times), place windows by replaying `osFocus` and `moveToWorkspace`, and call
  into the manager (`switchWorkspace`, `moveToWorkspace`, `rows`). Each rewrite keeps what the
  suite checks, through `command(_:)` and the readings of `Scenario`, adding an input to
  `Scenario` where one is missing.
- [ ] Rewrite `devdocs/testing.md` as the catalogue: every item becomes a row or moves down to a
  scenario test (what the ticks measured is already in `macos-behaviour.md`). Add the
  `test-runs/` format, and a passing run as a release step in `plans/alpha-release.md`.
- [ ] The fixture app and `devtools/e2e` for the rows driven by commands, with the report and
  `e2e manual`.
- [ ] CGEvent input in `devtools/e2e`: drags, modifier drags and resizes, pointer moves for focus
  follows mouse. Rows it automates leave the manual set.
- [ ] Update CLAUDE.md (Layout, Commands, Testing notes, the `testing.md` line in Status) and the
  live-check skill, which points at catalogue ids. Move the lasting decisions into
  `devdocs/design.md` and delete this plan.
