# 2026-10-31: an app ending on the window it remembers

A run between releases, for the fix for #87; the catalogue's rows weren't run.

- Date: 2026-10-31
- macOS: 26.7.2
- Build: 9f42abd, then 0246dfb with the review's fixes
- Displays: the built-in display, an external display above it
- Skipped contexts: displays side by side

Repeats by hand, with VS Code windows on both displays and focus follows mouse on: swipe the display
holding the window last used away, then rest the pointer on the window on the other display.

- About 10 repeats, then a few minutes of normal use. The focus ended on the remembered window 3
  times. tylerd asked again each time, the wanted window's focus came back in 9 to 12 ms, and no
  display switched. The focus stayed on the wanted window until the next action.
- In 16 other cases a focus passed through a parked window and the wait dropped it.
- No `window focus not held`, and no failed focus.
- One switch, to VS Code's workspace, with no request from tylerd before it: going to VS Code while
  setting up. It is followed as it should be.

On 0246dfb, the same repeats: the focus ended on the remembered window 4 times, tylerd asked again each
time, the wanted window's focus came back in 1 to 12 ms, and no display switched. No `window focus not
held`, and no failed focus.

cmd-` from VS Code on the built-in display to its window parked on the external display, twice, more
than a second after tylerd's last focus: the display switched to that workspace at once, and nothing
was asked back.

Not run: cmd-` within the 140 ms or so of tylerd's own focus on the app, where a real move is asked
back once.
