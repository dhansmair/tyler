# 2026-10-31: a rest focusing an empty workspace

A run between releases, for the rule that a rest of the pointer focuses an empty workspace; the
catalogue's rows weren't run.

- Date: 2026-10-31
- macOS: 26.7.2
- Build: a519285, 4cc69ec, then ddca1c0 with the overlay check
- Displays: the built-in display, an external display above it
- Skipped contexts: displays side by side

By hand, with focus follows mouse on, over about 15 minutes of checks and normal use:

- A rest on an empty workspace on the other display focused it, 11 times, with no failure. A terminal
  opened after that appeared there.
- A rest over the wallpaper of a workspace with windows changed nothing.
- No workspace switched on its own, and the keys didn't leave a window by accident in that time.

On ddca1c0, with the real overlay check: 11 more rests focused an empty workspace, and no workspace
switched on its own, so the Dock's window doesn't block the rule.

Not run: focus follows mouse off, and an overlay over an empty workspace (scenario tests cover both).
