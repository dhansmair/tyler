# 2026-10-31: an app ending on the window it remembers

A run between releases, for the fix for #87; the catalogue's rows weren't run.

- Date: 2026-10-31
- macOS: 26.7.2
- Build: 9f42abd
- Displays: the built-in display, an external display above it
- Skipped contexts: displays side by side

Repeats by hand, with VS Code windows on both displays and focus follows mouse on: swipe the display
holding the window last used away, then rest the pointer on the window on the other display.

- About 10 repeats, then a few minutes of normal use. The focus ended on the remembered window 3
  times. tylerd asked again each time, the wanted window's focus came back in 9 to 12 ms, and no
  display switched. Both of the second focus's windows held until the next action.
- In 16 other cases a focus passed through a parked window and the wait dropped it.
- No `window focus not held`, and no failed focus.
- One switch, to VS Code's workspace, with no request from tylerd before it: going to VS Code while
  setting up. It is followed as it should be.

Not run: cmd-` right after focus follows mouse focused a window, where a real move is asked back once.
