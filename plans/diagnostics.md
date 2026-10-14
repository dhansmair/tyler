# Diagnostics

## Why

When something doesn't work on real windows, nobody can see what tylerd sees. Two cases from the
grid's live check (2026-10-12):

- Focus follows mouse and dragging with the modifier both did nothing on one display, and worked
  on the other. From outside, every check they make looked fine: macOS reported the expected
  windows on top, and the tiling was right. The cause could only be guessed.
- A minimized window stayed tiled in tylerd's registry and held an empty slot. `tyler window list`
  showed the registry's view, so the difference from the window's real state went unnoticed.

The unified log doesn't help much either: reading it needs admin rights (`log stream` refuses
without them, and a sandboxed agent can't open the log store), and it holds everything, not just
what one check needs.

## Proposal

Each one its own increment, in this order:

1. **`tyler debug at [<x> <y>]`**: tylerd's view of one point on screen, the current pointer
   position if none is given. Its answer lists the display the point falls in (with its visible
   frame), the topmost window tylerd sees there (with its layer, and its workspace if it has one),
   whether that window is in view, whether a menu is open, the interaction state (idle, sliding,
   swiping, dragging), and what tylerd would do there: grab with the modifier or not, focus
   under focus follows mouse or not, **each with the reason** when not.
2. **`tyler debug windows`**: tylerd re-reads every window it tracks from macOS on the spot and
   prints only where that differs from what it believes (minimized, fullscreen, frame, title,
   kind), one line per difference, or "no differences". Then the windows macOS lists for the
   attached apps that tylerd doesn't track. It moves nothing and changes nothing.
3. **A log in `~/.tyler/tyler.log`, by level**: no command and nothing kept in memory. Every log
   call still goes to `Logger`; at or above `log.level` (a new setting, default `"warning"`) it
   also goes to stderr as one line: time, category, text. `tyler start` already sends stderr to
   `~/.tyler/tyler.log` and empties it at each start; run by hand, it shows in the terminal.
   `tyler config set log.level debug` turns detail up for a session, and a restart drops it
   again. Read with `tail` and `grep`.
4. **The live-check skill** runs `tyler debug at` (and `debug windows`) before asking the user to
   try something again.

## Decisions

| # | Question | Decision |
|---|----------|----------|
| D1 | Does the diagnosis repeat the guards of the modifier grab and focus follows mouse? | **No.** Their decisions move into one pure function in `TylerCore` (`PointerCheck`) that returns the window or the reason for refusing it. The real code and the diagnosis both call it, so they can't drift. |
| D2 | Where does `debug at` without coordinates get the pointer from? | **The client**, from `CGEvent(source: nil)?.location` (global coordinates, top-left origin, like AX's; no permission needed). The request always carries a point. |
| D3 | A `debug` command group in the manual? | **Yes**, under its own heading, marked as being for finding problems: the output may change in any release. |
| D4 | Whether macOS turned a tap off (`tapDisabledByTimeout`)? | Not in 1: `PointerInput` doesn't expose it. The log (3) shows it: the taps log it already. |
| D5 | The log in memory (a ring buffer behind `tyler debug log`) or in a file? | **The file tylerd already writes**, `~/.tyler/tyler.log`: nothing grows in RAM, nothing new to read it with, and it can be watched live (`tail -f`). It grows only while a chatty level is on, and starts empty at each start; a size cap waits until it is needed. |
| D6 | Which levels, and what does each hold? | `error` (something failed), `warning` (default: what a user should know, such as a refused tap), `info` (decisions: a focus asked for, a grab, a press passed on, a slide, a notification dropped), `debug` (each pointer rest, each AX call). The existing calls keep their levels (`notice` counts as `info`). |
| D7 | Does `debug windows` fix what differs? | **No**, it only reports. Fixing drift on each sync is a later step, once `debug windows` shows what drifts and how often (the known issue of the minimized window). |
| D8 | How does `debug windows` read fresh? | Through the backend: `snapshot()` already reads every tracked window again, and a new call lists each attached app's windows. The comparison is pure, in `TylerCore`, and unit tested. |
| D9 | Does writing the log block tylerd? | **Plain synchronous writes.** A write to a regular file only copies into the page cache (microseconds; no `fsync`), and lines below the level aren't even built (`@autoclosure`). Only a stderr that stops being read (a paused terminal, a stalled pipe, when tylerd runs by hand) could block it; guard against that only if it turns out to matter. |

## Increments

1. This plan. **Done.**
2. `PointerCheck` (pure, unit tested): the inputs (tiling, interaction idle, the point inside a
   display's visible frame, the topmost window, the windows in view, a menu open, the focused
   window, the button held, focus follows mouse on) and two decisions, `grab` and `focus`, each
   giving the window or a `PointerRefusal`. `grabbableWindow` and `focusWindow` use it, and
   `PointerFocus.target` becomes a call into it: a refactoring, so the existing tests
   (`PointerFocusTests`, `ModifierDragScenarios`, `FocusFollowsMouseScenarios`) stay unchanged. **Done.**
3. `Request.debugAt`, `Response.pointer(PointerDiagnosis)`, the CLI's `debug at`, its formatting,
   tests for each, and the manual entry. **Done.**
4. Use it on the display where focus follows mouse and the modifier fail; fix what it shows.
   **Done:** a Notification Centre window covered that display at layer 21; tylerd now skips
   every window above the normal layer that covers a whole display.
5. The live-check skill starts with `tyler debug at`; the tool's own filter follows the overlay rule. **Done.**
6. `debug windows`: the pure comparison (`WindowDrift`, unit tested: each field, untracked windows,
   none), the backend call that lists every attached app's windows (and its fake), the request,
   the CLI and its formatting, the manual entry. **Done.** Then `live-check` uses it.
7. The log: a `TylerLog` in `TylerCore` that every log call goes through (to `Logger`, and to a
   sink at or above the level), the sink in `tylerd` writing to stderr, `log.level` in the config
   (`docs/manual.md`, `docs/tyler.toml`, the personal config), and a look through the existing
   calls for the levels of D6 and for silent failures (a dropped AX update). **Done.** Then
   `live-check` reads the log's tail.
