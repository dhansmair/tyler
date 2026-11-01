# Changelog

tyler follows [semantic versioning](https://semver.org). Before 1.0, a minor version (0.x) may
change commands, the config file and the socket protocol; the entry says how.

## 0.3.0 (2026-11-01)

Focus and new windows that stay on the display in use. Commands, the config file and the socket
protocol stay compatible.

- `tyler logs` shows `tylerd`'s log and follows it, also across `tyler restart`.
- Choosing a layout briefly shows its name in the middle of the display. `layouts.notice = false`
  turns this off.
- A new window opens on the current workspace of the focused display, wherever macOS or the app
  first put it.
- The focused display follows the pointer: with `mouse.focus-follows` on, resting on an empty
  workspace focuses its display.
- Closing a window or quitting an app no longer switches to a parked workspace, and the focus stays
  on that display while it has windows left.
- With an app's windows on two displays, focusing one no longer slides the other display to the
  app's parked window.
- A window moved to another display lands in its slot, instead of staying tiled in the lists but
  floating on screen.
- After a burst of new windows, `tyler window close` closes the right window and keeps working.
- From macOS 15 on, a gap between windows shows the same resize cursor as a window's own edge.

## 0.2.1 (2026-10-30)

Fixes, and a Homebrew formula for each release.

- A window that can't be resized, such as a popup or a reminder, floats instead of being tiled.
- `tyler restart` while a display is unplugged keeps that display's workspaces, instead of merging
  them into the last workspace of the display that's left.
- `~/.tyler/tyler.log.1` keeps the previous run's log.
- Homebrew: each release from now on also gets a formula that stays at it,
  `brew install dhansmair/tyler/tyler@<version>`.

## 0.2.0 (2026-10-25)

An easier install.

- Homebrew: `brew install --HEAD dhansmair/tyler/tyler` from the tap
  [dhansmair/homebrew-tyler](https://github.com/dhansmair/homebrew-tyler).
- `tylerd` runs as `Tyler.app`, with an Accessibility permission of its own instead of the
  terminal's. `tyler start` copies it into `~/Applications`, where Spotlight finds it, and launches
  it; opening Tyler from Spotlight starts `tylerd` too. Started that way, `tylerd` opens
  `~/.tyler/tyler.log` itself.
- Without a code-signing identity the app is signed ad hoc, and macOS asks for the permission again
  after every update: `tyler restart` onto a new build puts every window back, removes the old
  entry in System Settings, and once the permission is given the windows go back to their
  workspaces. `make install SIGN_ID=<identity>` keeps the permission across updates.
- A second `tylerd` started while one runs quits without touching the running one's log.
- A floated window slides toward the middle of its display, and back when it is tiled again.
- Fixes after a display change or a wake: windows are placed only once the screen is unlocked, a
  window isn't forgotten because a move failed while the screen was locked, and windows missed
  while the displays settled are found.

## 0.1.0 (2026-10-21)

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
