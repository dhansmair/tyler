# Known issues

tyler is alpha software. These are the problems and limits known so far; please report anything
else (see [CONTRIBUTING.md](../CONTRIBUTING.md#reporting-a-bug)). The experimental `strip` layout
has its own list in [Layouts](layouts.md#strip--experimental).

## Bugs

- **A window of a slow or busy app may be missed** when `tylerd` starts or restarts while the app
  is busy (an IDE indexing, for example). It is picked up once you focus it; after a restart it may
  come back on the current workspace instead of its own.
- **Don't restart `tylerd` while the screen is locked**: macOS shows it no windows then, so every
  window comes back on its display's current workspace.
- **An Option-click can be lost** if `tylerd` was busy at that moment (an app not answering).
- **One window of a parked workspace may show at the left edge** with two displays side by side
  (seen once with Firefox).
- **A minimized window may keep its place in the layout** (seen once), which then shows as an
  empty slot. Restoring and minimizing it again fixes it.
- **Closing a window may switch workspaces** if macOS then focuses another window of the same app
  that is parked on another workspace (not confirmed).

## Limits

- **macOS keeps every window at least one point on screen**, so parked windows show as a thin
  column at the edge of the display. With the Dock on the left, windows parked at the left edge
  show a 56-point strip beside the Dock.
- **On a display with another display beside it, switching workspaces is instant** rather than a
  slide, so no window passes over the other display.
- **The middle display of three** has no free edge, and its parked windows lie on a neighbour.
- **Displays are numbered by position**, so a different display in the same place gets the same
  workspaces.
- **A crash or `kill -9` leaves windows parked** until the next `tyler start`.
- **Native fullscreen windows, windows on other macOS Spaces and menu bar apps** are left alone.
- **An app that doesn't answer slows tylerd down** for a second, the first time tylerd moves one
  of its windows. Its windows then stay where they are for 5 seconds (a command says they could
  not be placed); the first switch or command after that tries again.
- **Option-drag in apps** (Finder's copy, block selection in terminals) is tyler's while
  `mouse.modifier` is Option.
- **Terminals and windows with a minimum size** don't fill their slot exactly.

## Not there yet

- **Starting at login.** Start `tylerd` with `tyler start` from a terminal; see the
  [README](../README.md#starting-at-login).
- **Float rules** in the config file, beyond dialogs and `tyler window float`.
- **Signed binaries.** Install from source with `make install`.

## Not yet checked

Everything above was used daily on macOS 26 on an Apple silicon Mac, with one and two displays.
Older macOS versions, Intel Macs, three displays, and long sleeps where an external display drops
off haven't been tried.
