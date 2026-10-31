# 2026-10-31: the focus of a window opening in the frontmost app

A run between releases, for the fix that reads the focus of a window opening in the frontmost app; the
catalogue's rows weren't run.

- Date: 2026-10-31
- macOS: 26.7.2
- Build: 5adb8d0, then 363b4ec with the read narrowed to an app with no known focus
- Displays: the built-in display, an external display above it
- Skipped contexts: displays side by side

By hand: terminals opened in bursts with a shortcut, then closed quickly with another, with the keys
held so they repeat. 32 windows opened and 29 closed, each close followed by a focus, with no stall.
Before the fix, a close after such a burst took a window behind the front one, and the next closes
did nothing until a window was focused by hand.

Close commands repeating on a window already closing fail (41 in this run). It does no harm.

`displays changed` appeared in the log during the bursts (2 times), with no display touched. It had
no visible effect, and the cause isn't known.
