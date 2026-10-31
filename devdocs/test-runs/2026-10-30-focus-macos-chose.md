# 2026-10-30: the focus macOS picks after a close

A run between releases, for the rows that the fix for #12 touches; the other rows weren't run.

- Date: 2026-10-30
- macOS: 26.7.2
- Build: 80bb0c0
- Displays: the built-in display; an external display above it for the VS Code popup close
- Skipped contexts: displays side by side

| Id | Result | Notes |
|---|---|---|
| WIN-CLOSE-FOCUS | pass | AppKit fixture apps, 3 tries of each, focus declined every time: a close with a sibling in view (the sibling got the focus), a close leaving the workspace empty (no window kept the focus). VS Code, one try by hand: closing a window with the same app parked on another workspace, macOS focused the parked window and tylerd declined it. With two displays, one try by hand: closing a VS Code window through its confirmation popup, the same app parked on the other display. The popup closed, the focus went back to the window, the window closed, macOS focused the parked window, and tylerd declined it: no display switched. Not run: two closes in a row. |
| WS-CMD-TAB | pass | Posted cmd-tab to a fixture app's parked window, 5 of 5. A sixth try was dropped: another focus had got in first. |
| DISP-TILE | pass | By hand with an external display above the built-in one: each display switched through its own row, windows stayed on their display, commands and the menu bar followed the focused display. Not looked at: `display focus` leaving the focus on a parked window, which the plan leaves out. A window of an app with a window parked on the other display still slid that display (#87). |

Beyond the rows, also 3 tries each:

- Quitting an app with another app's window parked, a fixture app and TextEdit: declined every time.
  The focus came 12 to 19 ms before the quit reached tylerd for fixtures, 39 to 50 ms for TextEdit,
  so the registry knew by the end of the wait in every try and the window server's answer didn't
  decide any of them. It did answer "still there" in each cmd-tab above.
- Closing an app's last window, the app staying: no focus event, no switch. A cmd-tab to a parked
  window right after (about 1.8 s) switched.

Taking the focus back didn't flicker: the maintainer watched the fixture runs by eye.
