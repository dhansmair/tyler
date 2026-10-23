# Changelog

tyler follows [semantic versioning](https://semver.org). Before 1.0, a minor version (0.x) may
change commands, the config file and the socket protocol; the entry says how.

## 0.1.0 (2026-10-24)

The first alpha release.

- Tiling in the style of xmonad: each workspace is an ordered list of windows, laid out by `tall`
  (a main window on the left, the rest stacked on the right), `grid` (columns two windows high) or
  `full`. `strip`, a scrolling row of
  columns, is experimental.
- Workspaces side by side in a row on each display, switched with a horizontal slide, a three-finger
  trackpad swipe, Cmd-Tab or the menu bar.
- Several displays, each with its own row of workspaces; displays that come and go are followed.
- Mouse: resizing tiled windows moves the layout with them; dragging a window onto another swaps
  them, also across displays; Option-drag anywhere in a window moves or resizes it; optional focus
  follows mouse.
- Menu bar items: the workspace numbers as text, and a map of every workspace with its windows.
- The `tyler` command-line client for every action, its commands grouped by what they act on
  (`tyler window focus next`, `tyler workspace focus 2`), for binding to keys with skhd,
  Karabiner-Elements or Raycast.
- A config file (`~/.config/tyler/tyler.toml`) for gaps, workspaces, displays, app assignments,
  gestures, the mouse and the menu bar, applied with `tyler config reload`. `tyler config get` and
  `tyler config set` read and change one setting by its name in the file, `set` until tylerd
  stops.
- `tyler restart` keeps every window where it is; `tyler stop` puts every window back.
