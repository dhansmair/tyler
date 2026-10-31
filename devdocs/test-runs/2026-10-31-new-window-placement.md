# 2026-10-31: windows crossing displays

A run between releases, for the fixes that put a window crossing displays where it was asked to go
(#74); the catalogue's rows weren't run.

- Date: 2026-10-31
- macOS: 26.7.2
- Build: 831637e, then fc8a025 with the retry in `WindowMover`
- Displays: the built-in display, an external display above it
- Skipped contexts: displays side by side

By hand: terminals opened with a shortcut as fast as possible, up to six in a row, on both displays,
then closed. 17 windows opened, none logged `window placing off`, and each took its slot.

On fc8a025, with a key held to open them faster: 34 windows in about 3 s, none logged `window placing off`.

On the build before, one window in a dozen or so stayed off its slot, or stopped at the old display's
right edge.

Seen beside this, and not part of it: closing terminals quickly right after a burst of new ones can
leave tylerd with no focused window, although macOS shows one.
