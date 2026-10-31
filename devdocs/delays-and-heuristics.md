# Delays and heuristics

Every timer and rule of thumb in tyler, with why it is there and what it is based on. Plain visual
constants, such as the menu bar item's sizes, are left out. Keep this page current when one
changes. The measurements behind the values are in `macos-behaviour.md`, the decisions in
`design.md`.

The focus group is where most of the guessing is, because those values depend on macOS behaviour
that can only be measured.

## Focus: deciding what a focus event means

| What | Value | Why | Based on |
|---|---|---|---|
| A focus on a parked window must last before tylerd follows it (`parkedFocusSettling`) | 60 ms | Apps pass through the remembered window | Measured: passes within 21 ms |
| A closed window still counts as where the focus came from (`closedFocusMemory`) | 60 ms | Tells macOS's pick after a close from a later cmd-tab | Measured: 1 to 22 ms. The value is a judgment |
| tylerd's request stays remembered (`focusRequestMemory`) | 200 ms | An app ending on its remembered window counts as an answer to that request | Measured: slowest 120 ms. Small sample |
| Second request | Once, then a 60 ms wait, then follow | Keys never stay on a parked window | 8 of 8 held |

Rules with no timer:

- **tylerd's own focus:** a focus event tylerd expected is ignored once. If the app never sends it,
  the expectation can go stale (#11).
- **Who chose the window:** if the standard window that held the focus is gone, macOS picked the
  next one. Gone means missing from the registry or from the window server.
- **The display stays:** a focus in view on another display after such a close is refused at once,
  with no wait, as nothing slides.
- **Only standard windows count:** a dialog closing and focusing a parked window is taken as
  intended.
- **Chains:** in a chain of focuses, the first window counts.

Which window counts as new:

- **New:** a window on no workspace that has never been on one, and wasn't there when tylerd started
  or when tiling came back on. It joins the focused display, unless its app has a workspace or it
  opens under the pointer: browsers open a torn-off tab's window after the button comes up, up to
  1.6 s later.
- **Its first focus** doesn't move the focused display: the window may be anywhere, and it is about
  to move.

## Mouse

| What | Value | Why |
|---|---|---|
| `focus-delay`: the pointer must rest before focus follows it | 100 ms (configurable) | Avoids focusing everything the pointer passes over |
| `follow-interval`: pacing of drag steps | 16 ms (configurable) | Keeps up with fast input |
| A modifier press becomes a drag | 4 points of movement | Below that it is a click, which is passed on to the app |
| Smallest side when resizing | 50 points | Keeps a window usable |

A rest on an empty workspace focuses it, keys included; a rest over the wallpaper of a workspace with
windows does nothing. Focus follows mouse skips parked windows, windows above the normal layer, and anything while a menu
is open. The Dock and Notification Centre count as overlays when they cover a whole display.

## Swipes

| What | Value | Why |
|---|---|---|
| `swipe-distance`: travel for a whole workspace | 0.3 trackpad widths (configurable) | Feel |
| Fingers must move before the direction locks | 0.015 widths | Separates sideways from vertical |
| Release speed is read over the last | 50 ms | Reflects the flick, not the whole swipe |
| Flick speed that finishes a swipe under halfway | 1 display width per second | Feel |
| Going back takes at least | 60% of a slide | Settles visibly instead of snapping |
| Smoothing filter | 2 Hz when slow, up to about 30 Hz at quick speed | Steady when slow, responsive when fast |

## Slides and animation

| What | Value |
|---|---|
| Workspace slide | 250 ms, one frame every 8 ms |
| `swap`, `retile` | 250 ms each (configurable) |
| `drag-preview` | 200 ms (configurable) |

## Slow or unresponsive apps

| What | Value | Why |
|---|---|---|
| A single Accessibility call may block | 1 s | Stops one app freezing tylerd |
| An app that timed out is left alone for | 5 s | Otherwise it costs a second per window on every switch |
| Connecting to a new app | 6 tries, 500 ms apart | Apps aren't always ready when launched |

## Displays and the lock screen

| What | Value | Why |
|---|---|---|
| Wait after the last display change | 1 s | Measured: changes arrive over about 0.3 s, and macOS has finished by 1 s |
| Check for unlock | Every 1 s | macOS shows no windows at the lock screen |

- A window belongs to the display it overlaps most.
- A window counts as parked if 1 to 2 points of it still overlap the visible area.
- A move is skipped if the window is already close enough to its target.

## Background and lifecycle

| What | Value | Why |
|---|---|---|
| Re-enable event taps macOS turned off | Every 2 s | macOS disables slow taps |
| Check the Accessibility permission | Every 1 s | Starts, or removes taps, promptly |
| Restart hand-over file valid for | 60 s | Window IDs get reused after a reboot |
| `tyler start` and `stop` timeouts, access check, polling | 10 s, 10 s, 4 s, 100 ms | The client waits for `tylerd` |

## Deciding what a window is

`WindowKind.classify` can't rely on what apps report, because they misreport it in both directions:

- A dialog that offers full screen counts as a document (TextEdit's untitled documents).
- A standard window that can be neither closed nor minimized counts as a dialog.
- A window without full screen that can't be resized counts as a dialog, depending on its role.

## The ones to watch

`closedFocusMemory` and `focusRequestMemory` are the newest and have the least data behind them, and
a slow app could miss either. The result is then the old jump, not lost focus. #11 is the other weak
spot, because it has no timer at all. `parkedFocusSettling` adds 60 ms to every real switch to a
parked window, such as cmd-tab, which is the price of all of this.
