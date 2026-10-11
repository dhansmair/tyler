---
name: live-check
description: Check tyler against real windows and the real menu bar with devtools/live-check — where macOS really puts a window, the on-screen stacking order, what the menu bar item shows, and a replay of the workspace slide. Use after changing anything that moves or hides windows (slides, parking, layouts, focus), before ticking a "checked against real windows" item in devtools/ROADMAP.md, and when the user reports something odd on screen (a window "lost", a jump, a wrong direction).
---

# live-check

Unit tests use a fake backend that obeys every request. macOS doesn't: it clamps window positions, apps resize themselves, and windows hide behind each other. `devtools/live-check` looks at what really happens. It needs the terminal's Accessibility permission (the same grant tylerd uses) and compiles itself into `.build/live-check` on first use.

## Commands

| Command | What it tells you | Moves windows? |
|---|---|---|
| `devtools/live-check stacking` | On-screen windows front to back, each with its tyler workspace and title. Answers "where is my window?": hidden behind another (the `full` layout stacks them), parked (x near the right edge), or on no workspace. | no |
| `devtools/live-check menubar` | The text of tylerd's menu bar item and where it sits. Only the text: colours (faint numbers for empty workspaces) need the user's eyes. | no |
| `devtools/live-check displays` | Every display as tyler numbers it (the primary first, then left to right, then top to bottom), with its id, UUID, frame, visible frame, and the edge tyler would park at. Also whether "Displays have separate Spaces" is on. | no |
| `devtools/live-check positions <id> [x y] [--display <n>]` | Asks macOS to put the window at each edge of a display, the primary unless `--display` says otherwise (or at one position), and prints what it got, marking `CLAMPED` requests. Use it before relying on any new position, such as a new parking spot or slide path. | yes, briefly, then puts it back |
| `devtools/live-check slide <seconds> <rounds> <out-ids> <in-id@x,y>...` | Replays a workspace switch: the `out` windows slide left while the `in` windows come in from the right edge into their slots, then back. Every window ends where it started. For judging a change to the motion by eye before building it into tylerd. | yes, for the whole replay |
| `devtools/live-check gestures <seconds>` | Logs trackpad contacts of 3 or more fingers (event count, horizontal and vertical travel in trackpad widths) from a listen-only event tap and from a global `NSEvent` monitor, then a summary per source. The user does the swiping. | no |

Get window ids and slots from `tyler list` (`.build/debug/tyler list`). Example: `devtools/live-check slide 0.25 2 6250,7110 3993@67,51` slides two windows out while window 3993 comes into the slot at 67,51.

## Rules

- **Prefer reading to moving.** Start with `stacking`, `menubar` and `tyler list`. Move windows only when the question needs it.
- **Tell the user before moving their windows**, and for `slide` give the countdown time to watch: they judge smoothness, not you. Ask them what they saw instead of guessing.
- **Don't run `tyler stop` without asking.** It puts every window back where it was before tylerd moved it, so the user loses their arrangement. `tyler restart` keeps the windows in place (the old tylerd hands its workspaces over), so it's safe after a rebuild; still say that you're restarting.
- **Check that windows went back** afterwards with `tyler list`.
- **Write findings down.** Measured limits and verified checklist items go into `devtools/ROADMAP.md` with the date and macOS version, the way the M4 notes record the position limits.

In zsh, pass `x y` as separate words: an unquoted `$p` holding "x y" stays one argument, and `positions` then sweeps every edge. That sweep moved a window on the Dell onto the laptop, and tylerd tiled it.

## Known limits (macOS 26.7, measured 2026-10-10)

A window must overlap the visible frame (the display minus the menu bar and Dock) by at least 1 point horizontally; a request further out is pulled 40 points back in. It can't go above the menu bar, and at the bottom 32 points stay visible. A display without the menu bar keeps a strip clear at the top all the same (30 points on a 2560×1440 Dell, measured 2026-10-11), although its visible frame covers the whole display. `positions` re-measures this; if it disagrees with this table, macOS changed, and so must `Parking` in `Sources/TylerCore/Parking.swift`.

## Extending

The tool's sources are in `devtools/LiveCheck/` (`main.swift` holds the commands, `Slide.swift` the replay). They are plain Swift with no package, and the pre-commit hook lints them like the rest of the repo. Add a command when a check is needed a second time; one-off probes can stay in the scratchpad.
