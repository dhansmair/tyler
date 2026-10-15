# Testing strategy

tyler is tested in three layers, a pyramid: many fast unit tests, fewer scenario tests of the
whole server on fakes, and a small end-to-end suite on real windows that runs before every
release. This file says what each layer covers and where a new test goes.

## The layers

| Layer | Covers | Where | Run |
|---|---|---|---|
| Unit (`make test-unit`) | A pure decision (TylerCore), one controller on a `Model` and `ControllerContext`, a plain server type (Animator, Debounce, WindowRegistry), the window system on fake Accessibility and workspace clients, config, wire format, CLI parsing | `Tests/<Target>Tests/`, mirroring the sources (`devtools/check-test-paths`) | every commit |
| Scenario (`make test-scenario`) | The whole server on fakes: displays, windows and workspaces given; an input (a command, a window event, a swipe, a drag, a display change); the lists, frames, focus and parking that come out | `Tests/TylerScenarioTests/<Feature>/` (the older ones are built on `ManagerHarness` directly) | every commit |
| End to end | Real tylerd on real macOS: the AX layer, the event taps, timing, where macOS clamps a window, the menu bar | `devdocs/testing.md`; `devtools/live-check` | before every release, and after changing anything that moves windows |

## Where a test goes

At the lowest layer where the bug could show.

- **Unit** for a single decision: where a layout puts its windows, where a swipe settles, what a
  controller returns for an input. Decisions in TylerCore are tested without fakes.
- **Scenario** for a behaviour `docs/` promises, seen from outside the server (*with three
  windows in `tall`, dragging the main window onto the stack puts it there*), and for bugs in the
  plumbing between parts: an event that reached the wrong controller, an echo that wasn't
  filtered, effects run in the wrong order. A scenario sets up its context, gives one input and
  checks what comes out. It doesn't reach into a controller.
- **End to end** only for what macOS decides: whether an AX call does what it says, whether a tap
  sees an event, timing, clamping, the menu bar. If an end-to-end item checks only logic, it
  belongs in a scenario test.

A bug fix comes with a regression test at the layer the bug could have been caught at, usually
the lowest.

## Writing a scenario test

```swift
@Test func droppingTheMainWindowOnTheStackSwapsIt() async {
  let scenario = await Scenario(workspaces: [1: [1, 2, 3]], layout: .tall)
  await scenario.drag(1, by: CGVector(dx: 900, dy: 300))
  #expect(scenario.list(1) == [2, 1, 3])
  #expect(scenario.frame(of: 2) == scenario.rect(.leftHalf))
}
```

- **The context:** `Scenario(displays:workspaces:showing:layout:config:)`. tylerd starts from it
  as after a restart, so the test doesn't replay commands to get there.
- **The input**, in the words of `docs/`: `command("workspace focus next")` (through the real CLI
  parser), `focus`, `drag`, `swipe`. Each runs until things are quiet: the events handled and the
  clock advanced until nothing waits on it. Add an input to `Scenario` when a test needs one.
- **What the user sees:** `list(_:)`, `frame(of:)`, `rect(_:display:)`, `isParked(_:)`, `shown`,
  `focused`, checked with plain `#expect`.
- A scenario goes through what tylerd is given (a command, an event) and reads what it did. It
  doesn't call into the manager or a controller, so the inside can be restructured without
  touching it.

## Expected values

Write the expected result independently of the code under test. A frame is a literal rect, or
worked out in the test from the display (a `Region`, such as `.leftHalf`), never by calling the
layout being tested. The frames a layout should produce are listed in `docs/layouts.md`, so a test can follow them.

## The end-to-end suite

`devdocs/testing.md` lists what to run on real windows. The whole list is run before every
release, as a regression suite, not ticked off once: something that worked on an earlier build
says nothing about this one. Keep the list short. Anything that can be checked by a scenario test
belongs there, and anything that can be checked by a script (`devtools/live-check`, `tyler window
list --json`, `tyler debug windows`) shouldn't wait for a person.
