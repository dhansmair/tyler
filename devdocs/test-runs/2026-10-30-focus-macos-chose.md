# 2026-10-30: the focus macOS picks after a close

A run between releases, for the rows that the fix for #12 touches; the other rows weren't run.

- Date: 2026-10-30
- macOS: 26.7.2
- Build: 80bb0c0
- Displays: the built-in display
- Skipped contexts: two displays, Electron apps

| Id | Result | Notes |
|---|---|---|
| WIN-CLOSE-FOCUS | pass | AppKit fixture apps, 3 tries of each, focus declined every time: a close with a sibling in view (the sibling got the focus), a close leaving the workspace empty (no window kept the focus). Not run: the parked window on another display, and VS Code with its confirmation popups. |
| WS-CMD-TAB | pass | Posted cmd-tab to a fixture app's parked window, 5 of 5. A sixth try was dropped: another focus had got in first. |
| DISP-TILE | skipped | Needs two displays. |

Beyond the rows, also 3 tries each:

- Quitting an app with another app's window parked, a fixture app and TextEdit: declined every time.
  The focus came 12 to 19 ms before the quit reached tylerd for fixtures, 39 to 50 ms for TextEdit,
  so the registry knew by the end of the wait in every try and the window server's answer didn't
  decide any of them. It did answer "still there" in each cmd-tab above.
- Closing an app's last window, the app staying: no focus event, no switch. A cmd-tab to a parked
  window right after (about 1.8 s) switched.

Taking the focus back didn't flicker: the maintainer watched the fixture runs by eye.
