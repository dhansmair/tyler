# 2026-10-31: the focus staying on its display

A run between releases, for the fix that keeps the focus on its display; the catalogue's rows weren't
run.

- Date: 2026-10-31
- macOS: 26.7.2
- Build: 329b70a
- Displays: the built-in display, an external display above it
- Skipped contexts: displays side by side

By hand, closing a terminal on the built-in display after focusing a terminal on the external one:

- With another window left on the workspace, 2 tries: macOS focused the external terminal 11 to 22 ms
  after the close, tylerd declined it at once, and the focus was back on the built-in display 38 to
  43 ms later. The external display's window shows as focused for that long.
- With the workspace left empty, 1 try: declined, and the focus stayed off the external terminal.

A terminal opened right after that, with `open -n`, appeared on the external display. Where a new
window opens isn't part of this fix; macOS or the app decides.
