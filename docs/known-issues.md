# Known issues

tyler is alpha software. These are the problems and limits known so far; each has a
[GitHub issue](https://github.com/dhansmair/tyler/issues) to follow or add to. Please report anything
else (see [CONTRIBUTING.md](../CONTRIBUTING.md#reporting-a-bug)). The experimental `strip` layout
has its own list in [Layouts](layouts.md#strip--experimental).

## Bugs

- **Switching off or removing the Accessibility permission while `tylerd` runs can freeze the
  Mac** if it happens while you hold the modifier or the pointer is over a gap between windows:
  the pointer moves, but nothing can be clicked or typed until a forced restart. This is a macOS
  bug that hits any app that takes over mouse presses. Run `tyler stop` first. ([#3](https://github.com/dhansmair/tyler/issues/3))
- **A window of a slow or busy app may be missed** when `tylerd` starts or restarts while the app
  is busy (an IDE indexing, for example). It is picked up once you focus it, and after a restart
  it goes back to its own workspace. ([#6](https://github.com/dhansmair/tyler/issues/6))
- **An Option-click can be lost** if `tylerd` was busy at that moment (an app not answering). ([#4](https://github.com/dhansmair/tyler/issues/4))
- **One window of a parked workspace may show at the left edge** with two displays side by side
  (seen once with Firefox). ([#5](https://github.com/dhansmair/tyler/issues/5))
- **A minimized window may keep its place in the layout** (seen once), which then shows as an
  empty slot. Restoring and minimizing it again fixes it. ([#8](https://github.com/dhansmair/tyler/issues/8))
- **A window `tylerd` finds late may jump to the focused display,** as it counts as new: one of an
  app that wasn't answering when `tylerd` started. ([#99](https://github.com/dhansmair/tyler/issues/99))
- **A window opened in the background** (`open -g`) of an app with a workspace in the config
  brings that workspace into view, although the app you were using stays in front. ([#72](https://github.com/dhansmair/tyler/issues/72))
- **A window sent alone to a larger display** may arrive narrower than its slot;
  `tyler workspace retile` fixes it. ([#74](https://github.com/dhansmair/tyler/issues/74))

## Limits

- **macOS keeps every window at least one point on screen**, so parked windows show as a thin
  column at the edge of the display. With the Dock on the left, windows parked at the left edge
  show a 56-point strip beside the Dock. ([#13](https://github.com/dhansmair/tyler/issues/13))
- **On a display with another display beside it, switching workspaces is instant** rather than a
  slide, so no window passes over the other display. ([#14](https://github.com/dhansmair/tyler/issues/14))
- **The middle display of three** has no free edge, and its parked windows lie on a neighbour. ([#15](https://github.com/dhansmair/tyler/issues/15))
- **Displays are numbered by position**, so a different display in the same place gets the same
  workspaces. ([#17](https://github.com/dhansmair/tyler/issues/17))
- **A crash or `kill -9` leaves windows parked** until the next `tyler start`. ([#18](https://github.com/dhansmair/tyler/issues/18))
- **Native fullscreen windows, windows on other macOS Spaces and menu bar apps** are left alone. ([#19](https://github.com/dhansmair/tyler/issues/19))
- **An app that doesn't answer slows tylerd down** for a second, the first time tylerd moves one
  of its windows. Its windows then stay where they are, and aren't focused, for 5 seconds (a
  command says so); the first switch or command after that tries again. ([#20](https://github.com/dhansmair/tyler/issues/20))
- **Option-drag in apps** (Finder's copy, block selection in terminals) is tyler's while
  `mouse.modifier` is Option. ([#21](https://github.com/dhansmair/tyler/issues/21))
- **Terminals and windows with a minimum size** don't fill their slot exactly. ([#22](https://github.com/dhansmair/tyler/issues/22))

## Not there yet

- **Starting at login.** Start `tylerd` with `tyler start` from a terminal; see the
  [README](../README.md#starting-at-login). ([#23](https://github.com/dhansmair/tyler/issues/23))
- **Float rules** in the config file, beyond dialogs and `tyler window float`. ([#24](https://github.com/dhansmair/tyler/issues/24))
- **Signed binaries.** Homebrew and `make install` build from source, signed ad hoc, so macOS asks for the permission again after each update. ([#26](https://github.com/dhansmair/tyler/issues/26))

## Not yet checked

Everything above was used daily on macOS 26 on an Apple silicon Mac, with one and two displays.
Older macOS versions, Intel Macs, three displays, and long sleeps where an external display drops
off haven't been tried ([#42](https://github.com/dhansmair/tyler/issues/42)).
