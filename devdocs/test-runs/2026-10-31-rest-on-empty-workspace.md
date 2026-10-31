# 2026-10-31: a rest focusing an empty workspace

A run between releases, for the rule that a rest of the pointer focuses an empty workspace; the
catalogue's rows weren't run.

- Date: 2026-10-31
- macOS: 26.7.2
- Build: a519285, then 4cc69ec
- Displays: the built-in display, an external display above it
- Skipped contexts: displays side by side

By hand, with focus follows mouse on, over about 15 minutes of checks and normal use:

- A rest on an empty workspace on the other display focused it, 11 times, with no failure. A terminal
  opened after that appeared there.
- A rest over the wallpaper of a workspace with windows changed nothing.
- No workspace switched on its own, and the keys didn't leave a window by accident in that time.

Not run: focus follows mouse off, and an overlay over an empty workspace (scenario tests cover both).
