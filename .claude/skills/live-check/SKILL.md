---
name: live-check
description: Check tyler against real windows and the real menu bar with devtools/live-check — where macOS really puts a window, the on-screen stacking order, what the menu bar item shows, and a replay of the workspace slide. Use after changing anything that moves or hides windows (slides, parking, layouts, focus), when running a row of the devdocs/testing.md catalogue, and when the user reports something odd on screen (a window "lost", a jump, a wrong direction, focus follows mouse or dragging with the modifier doing nothing). Starts with `tyler debug at`, tylerd's own view of a point.
---

# live-check

Unit tests use a fake backend that obeys every request. macOS doesn't: it clamps window positions, apps resize themselves, and windows hide behind each other. `devtools/live-check` looks at what really happens. It needs the terminal's Accessibility permission (the same grant tylerd uses) and compiles itself into `.build/live-check` on first use.

## Start with tylerd's own view

Before asking the user to try something again, ask tylerd what it sees. Its `debug` commands report the decisions the real code makes, with the reason when it does nothing:

- **`tyler debug at [<x> <y>]`**: at a point (the pointer's if none is given), the display and its visible frame, the window on top as tylerd sees it, whether a menu is open, the interaction under way, tiling, and whether a press with the modifier would grab and focus follows mouse would focus, each with its reason. Use it whenever focus follows mouse or dragging with the modifier "does nothing", on every display involved: run it at a point inside each of the windows in question. To check where the user's pointer is, have them point and run `sleep 3; tyler debug at`.

`debug at` needs a `tylerd` from the same build: after `make build`, `tyler restart` first (it says "unknown request" otherwise). A restart can clear a stuck state, so look with what is there (`stacking`, `pointer`, the commands below) before restarting, if the running `tylerd` is older.

## Commands

| Command | What it tells you | Moves windows? |
|---|---|---|
| `devtools/live-check stacking` | On-screen windows front to back, each with its tyler workspace and title. Answers "where is my window?": hidden behind another (the `full` layout stacks them), parked (x near the right edge), or on no workspace. | no |
| `devtools/live-check menubar` | The text of tylerd's menu bar item and where it sits. Only the text: colours (faint numbers for empty workspaces) need the user's eyes. | no |
| `devtools/live-check displays` | Every display as tyler numbers it (the primary first, then left to right, then top to bottom), with its id, UUID, frame, visible frame, and the edge tyler would park at. Also whether "Displays have separate Spaces" is on. | no |
| `devtools/live-check positions <id> [x y] [--display <n>]` | Asks macOS to put the window at each edge of a display, the primary unless `--display` says otherwise (or at one position), and prints what it got, marking `CLAMPED` requests. Use it before relying on any new position, such as a new parking spot or slide path. | yes, briefly, then puts it back |
| `devtools/live-check resize <id> <x> <y> <w> <h> [--order size-first\|move-first]` | Writes the frame write by write, in tylerd's order (size, position, size) and moved first, each from where the window was, and prints the frame after every write: `ok`, `REFUSED` (the size didn't change), `OTHER SIZE` (the app chose one, as terminals round to rows) or `CLAMPED`. For a window that won't take its slot. Results are only clean while nobody else (the user, tylerd following a drag) moves the window. | yes, briefly, then puts it back |
| `devtools/live-check slide <seconds> <rounds> <out-ids> <in-id@x,y>...` | Replays a workspace switch: the `out` windows slide left while the `in` windows come in from the right edge into their slots, then back. Every window ends where it started. For judging a change to the motion by eye before building it into tylerd. | yes, for the whole replay |
| `devtools/live-check display-events <seconds> [settle]` | Logs what macOS reports while displays change (reconfiguration callbacks with their flags, the screen-parameters notification, sleep and wake). After each burst, once `settle` seconds (default 1) have passed without events, it prints the displays and every window's frame with the display it is on. The user does the plugging, the lid and the rearranging; write the output to a file and read it afterwards. | no |
| `devtools/live-check pointer <seconds> [rest-ms]` | At each rest of the pointer (default 100 ms): the topmost on-screen window under it with its layer and owner, the one tylerd sees (without the windows above the normal layer that cover a whole display: the Dock's, Notification Centre's), every window above the normal layer (open menus, the Dock, the menu bar; status items left out), and how long the window list took. What focus follows mouse sees. The user moves the pointer and opens menus; it prints line by line, so a log file can be read while it runs. | no |
| `devtools/live-check mod-drag <seconds> [modifier] [stall-ms]` | An active event tap holds each mouse-down made with the modifier (default `option`, or e.g. `ctrl+option`): past a 4-point move it logs a move (left button) or a resize (right) and swallows the rest of the gesture; a click is posted again so the app still gets it. Logs every mouse-down, the window under it and how long the window list took. `stall-ms` blocks the main thread at each held press, to see macOS turn a slow tap off. Moves no window. The user makes the clicks and drags. | no |
| `devtools/live-check key <combination>...` | Presses key combinations as if typed (`option+shift+j`; letters are ANSI key positions), posted at the HID tap so hotkey daemons and keystroke overlays see them. For a scripted demo video, and for checking a binding fires. | only through what the keys are bound to |
| `devtools/live-check gestures <seconds>` | Logs trackpad contacts of 3 or more fingers (event count, horizontal and vertical travel in trackpad widths) from a listen-only event tap and from a global `NSEvent` monitor, then a summary per source. The user does the swiping. | no |

Get window ids and slots from `tyler window list` (`.build/debug/tyler window list`). Example: `devtools/live-check slide 0.25 2 6250,7110 3993@67,51` slides two windows out while window 3993 comes into the slot at 67,51.

## Rules

- **Prefer reading to moving.** Start with `stacking`, `menubar` and `tyler window list`. Move windows only when the question needs it.
- **Tell the user before moving their windows**, and for `slide` give the countdown time to watch: they judge smoothness, not you. Ask them what they saw instead of guessing.
- **Check the screen isn't locked before restarting `tylerd`** (`ioreg -n Root -d1 | grep IOConsoleLocked` says `No`): while it is, the Accessibility API shows no windows and the new `tylerd` finds none: each window gets its workspace back only when it appears after the unlock. Live checks can't run on a locked screen either.
- **Don't run `tyler stop` without asking.** It puts every window back where it was before tylerd moved it, so the user loses their arrangement. `tyler restart` keeps the windows in place (the old tylerd hands its workspaces over), so it's safe after a rebuild; still say that you're restarting.
- **Check that windows went back** afterwards with `tyler window list`.
- **Write findings down.** Measured behaviour goes into `devdocs/macos-behaviour.md` with the macOS version and the setup in general terms; the result of a catalogue row goes into the run's file in `devdocs/test-runs/` (`devdocs/testing.md`, "Recording a run").

In zsh, pass `x y` as separate words: an unquoted `$p` holding "x y" stays one argument, and `positions` then sweeps every edge. That sweep moved a window on the external display onto the laptop, and tylerd tiled it.

## Known limits (macOS 26.7, measured 2026-10-10)

A window must overlap the visible frame (the display minus the menu bar and Dock) by at least 1 point horizontally; a request further out is pulled 40 points back in. It can't go above the menu bar, and at the bottom 32 points stay visible. A display without the menu bar keeps a strip clear at the top all the same (30 points on an external display, measured 2026-10-11). `NSScreen.visibleFrame` leaves it out only after `NSApplication.shared` exists: a tool that reads screens without creating the app sees the whole display. `positions` re-measures this; if it disagrees with this table, macOS changed, and so must `Parking` in `Sources/TylerCore/Placement/Parking.swift`.

## Extending

The tool's sources are in `devtools/LiveCheck/` (`main.swift` holds the commands, `Slide.swift` the replay). They are plain Swift with no package, and the pre-commit hook lints them like the rest of the repo. Add a command when a check is needed a second time; one-off probes can stay in the scratchpad.
