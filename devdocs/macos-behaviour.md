# What macOS does

Measured with `devtools/live-check` on macOS 26.7 (Apple silicon), October 2026, unless noted.
These facts are why tyler parks and slides the way it does (`design.md`); they are hard to find in
Apple's documentation. Re-measure after a major macOS update, and record new findings here with the
macOS version and the setup described in general terms.

## Where a window may go

- **A window must overlap its display's visible frame (Dock excluded) by at least 1 point
  horizontally.** `x = visibleMaxX − 1` and `x = visibleMinX − width + 1` are accepted; anything
  further out is pulled back to 40 points inside. With the Dock on the left, the left limit leaves
  a 56-point strip of the window beside the Dock.
- **Vertically, macOS clamps in both directions.** A position above the menu bar lands just below
  it; one below the screen lands at `maxY − 32`. So a window can't slide out through the top or
  bottom, which is why tyler's slide is horizontal.
- **A display without the menu bar still keeps a strip clear at the top** (30 points measured on an
  external display). Maximised windows there stop below it.
- **`NSScreen.visibleFrame` is only right once the process has created `NSApplication.shared`**;
  before that it reports the whole display.
- **A window that crosses onto a shorter display is cut to that display's height** and keeps that
  size when it comes back. Another reason nothing slides onto a neighbouring display.
- **A window that reaches past the bottom of its display onto the display below is clamped when it
  shrinks to just above that edge.** With the bottom edge asked for within about 25 points above
  the display's (23 points clamped, 33 not), macOS puts it 63 points onto the display below
  instead; asked for higher up, the window gets the size asked for. A window already at that line
  seems not to shrink at all. A window that lies on its display shrinks as asked, and growing it
  stops at the display's edge. So a window that reaches past the edge (moved before it was
  resized, or rounded up by a terminal) can't shrink into a slot at the bottom of the display:
  `MacWindowSystem.setFrame` first moves it up so it doesn't reach past its new frame. Measured
  2026-10-12 on a terminal window at the bottom of an external display above the built-in one,
  with `live-check resize`.
- **Dialogs are accepted anywhere**, even past the edges, and their position isn't reported back.
  They aren't tiled, so this doesn't matter for parking.
- **Some apps enforce a minimum size** (System Settings: 723 × 470) and terminals snap to character
  cells, so a window may not fill its slot exactly. Ghostty 1.3 rounds a height set through AX up
  to the next whole row, even with `window-step-resize` off (asked for 630 points it took 640, for
  643 it took 662), so a bottom window can reach a few points past its display.

- **While the screen is locked, the Accessibility API reports no windows**: a `tylerd` started
  then found none (`tyler window list`: "no windows", `tyler debug windows`: 0 windows), while the
  window server still listed every one (`live-check stacking`). Seen 2026-10-13 on macOS 26.7,
  checked with `ioreg -n Root -d1 | grep IOConsoleLocked`.

## Window kinds

Measured 2026-10-14 on macOS 26.7, with TextEdit and a probe that read each window's role,
subrole, title-bar buttons and whether its size can be set:

| Window | Subrole | Full screen button | Close, minimize | Size settable |
|---|---|---|---|---|
| Untitled document made by AppleScript while TextEdit is in the background | `AXDialog` | yes | yes | yes |
| The same documents once TextEdit has been frontmost | `AXStandardWindow` | yes | yes | yes |
| A document opened from a file | `AXStandardWindow` | yes | yes | yes |
| The About window | `AXDialog` | no | yes | no |
| The Open panel (File > Open) | `AXStandardWindow` | no | no | yes |

- **The subrole changes when the app first becomes active**, with no notification tylerd hears, so
  a kind read from the subrole once stays wrong. The buttons are there from the start (read
  0.3 s after the window appeared).
- **The normal windows of the other apps checked** (a terminal, an editor, a browser, an Electron
  app) all have close, minimize and full screen buttons. `WindowKind.classify` relies on that.

## Speed

- **An AX position write takes 1–3 ms.** A slide is limited by the number of windows and by slow
  apps, not by AX itself. An app that doesn't answer blocks the caller up to the messaging timeout
  (tylerd sets 1 s).
- **The window list** (`CGWindowListCopyWindowInfo`, on-screen only) takes about 0.6 ms with 50
  windows, and 20–30 ms on the first call in a process.
- **The window under a mouse-down** takes 1–5 ms.
- **What slides, swipes and drags cost** (the `finished` lines at `log.level` `info`; one display,
  workspaces of 1–4 windows of terminals, an editor and browsers; macOS 26.7, October 2026, before
  the speed-ups of October 2026):

  | Interaction | Frames | Longest gap | Per write | Slowest write |
  |---|---|---|---|---|
  | Slide (2–4 windows) | 19–29 of 31 | 16–56 ms | 0.5–1.8 ms | 5–47 ms (a browser, a terminal) |
  | Swipe (quick, 3–4 windows) | 3–7 | 17–35 ms | 1–2.5 ms | 2–9 ms |
  | Resize by an edge or a gap (`tall`, 3 windows) | 9–32 | 110–180 ms | 18–23 ms | 28–43 ms (a terminal) |

  Position writes are cheap, and a slide loses frames to the odd slow write: one browser write of
  47 ms cost a slide 8 of its 31 frames. A swipe step takes its writes plus the throttle's 8 ms,
  about 17–20 ms. Resizing is ten times slower per write: each neighbour gets a full `setFrame`
  (size, position, size, read back), and a terminal reflows on every size change. One resize of
  about 5 s spent 2.2 s in writes on the main thread and brought back 472 window updates, each
  read in full.

  With two writes per neighbour while a resize is in progress (`FrameWrite.inPassing`, no read
  back) a write takes 6–10 ms (14–16 ms with more windows), and a resize gets 2–4 times as many
  steps. A drag's longest gap also counts the time the pointer rested, so it says little.

## Displays that change

- **Display ids and UUIDs stay the same** across unplugging and replugging, clamshell mode, sleep
  and rearranging. UUIDs (`CGDisplayCreateUUIDFromDisplayID`) also survive a reboot.
- **Each change arrives as a burst**: reconfiguration callbacks, a `didChangeScreenParameters`
  notification, more callbacks with their flags, and a second notification about 0.3 s later. One
  second after the last notification, `NSScreen` is current and macOS has finished moving windows.
- **Unplugging** moves the windows of the display that went away onto the remaining one, resized to
  fit (some partly off screen). **Replugging or opening the lid** puts every window back exactly.
- **Clamshell mode** makes the external display the main one at (0, 0); the Dock and the built-in
  display's windows move to it.
- **macOS pulls parked windows back on screen when the displays change**, even on a display that
  stayed. So after every change tylerd places every window again.
- **Plugging a display in also sends `activeSpaceDidChange`.**
- **A short sleep and wake** sends only `willSleep`, `screensDidSleep`, `screensDidWake` and
  `didWake`. A long sleep, where an external display may drop off, is unmeasured.
- **"Displays have separate Spaces"** doesn't change the parking limits above.

## Events and taps

- **Trackpad gestures**: a listen-only `CGEventTap` for gesture events (type 29) gets every touch
  frame, even with 3- and 4-finger swipes assigned to Spaces; `NSEvent(cgEvent:).allTouches()` gives
  finger count and positions. A global `NSEvent` monitor for `.gesture` gets nothing. A 3-finger
  swipe gives 30–55 frames (about 100 per second) and about 0.2 trackpad widths of travel; fingers
  land and lift one at a time, so short blips with other finger counts happen.
- **Pointer moves**: a listen-only tap for `.mouseMoved` sees synthetic moves that a global
  `NSEvent` monitor doesn't. A move with a button held is `mouseDragged`.
- **An active session tap** (`.defaultTap`) on mouse down, dragged and up can swallow events and
  needed no permission beyond the terminal's existing grants. Posting a held click again (marked in
  `eventSourceUserData` so the tap lets it through) works, click count included.
- **A slow tap is turned off** (`tapDisabledByTimeout`, seen with the main thread blocked 1.5 s).
  Turning it back on works, but the press in progress is lost: the app gets the drags and the
  mouse-up without the mouse-down.
- **Minimizing** (measured 2026-10-12, macOS 26.7, a terminal window minimized with Cmd-M and
  restored from the Dock, three times): `AXMinimized` already reads `true` when
  `kAXWindowMiniaturizedNotification` arrives, and `false` when `kAXWindowDeminiaturizedNotification`
  does, and stays so 100 and 500 ms later. Reading the attribute at the notification is reliable.
- **Revoking Accessibility with an active tap alive can stop all input** (reported on Apple's
  developer forums, threads 844416 and 735204, FB24619068, macOS 15 to 27; seen once here on
  macOS 26.7, not reproduced on purpose): with a `.defaultTap` session tap in place, even one
  passing every event through and getting no `tapDisabled…` event, switching off or removing the
  responsible app's grant leaves the pointer moving but clicks and keys undelivered, until a forced
  restart. Listen-only taps are not affected. Per the reports, removing the entry with `−` leaves
  `AXIsProcessTrusted()` true and posts no `com.apple.accessibility.api` notification; switching
  it off does both. Never try it on a Mac in use.
- **No new permission prompt** was needed for any of these taps from a terminal that already had
  Accessibility.

- **An app with only off-screen windows may refuse to be observed** (seen once, 2026-10-12, macOS
  26.7): an Electron app whose only window was minimized or hidden wasn't attached after a
  restart (`tyler debug windows` listed it under "apps tylerd can't observe"); brought to the
  front, it attached and its window tiled. Why it refused isn't known: the reason is only in a
  `Logger` debug line.
- **A freshly launched app comes to the front before it can be observed** (seen 2026-10-14,
  macOS 26.7, a terminal whose shortcut starts a new process for each window, twice in a row):
  the first attach failed registering `kAXWindowCreatedNotification`, while the app's
  `didActivateApplicationNotification` had already come. The retry attached it and tiled its
  window, but nothing read its focused window, so tylerd kept the previous window as focused and
  `window swap` moved that one. Attaching the frontmost app now reads its focus.
- **An app that quits by itself posts no `didTerminateApplicationNotification`** (measured
  2026-10-14, macOS 26.7): Find My, a Mac Catalyst app, quits when its last window closes, and a
  listener got its launch notification but no terminate notification within 15 s, nor did the
  window send `kAXUIElementDestroyedNotification`. AX calls to its windows then fail with
  `cannotComplete` (-25204), not `invalidUIElement`. The app does leave
  `NSWorkspace.runningApplications` (a KVO removal, on the main thread) and its `isTerminated`
  turns true, at the same moment. The `NSRunningApplication` in that removal already says -1 for
  its `processIdentifier` (measured 2026-10-14 with Calculator), so it can't name the app that
  quit: compare the process ids still running instead. An app told to quit (Calculator, `quit app`) shows up in all of
  them.

## The cursor from the background

Measured 2026-10-14 on macOS 26.7, with tylerd in the background and the pointer moved by synthetic
moves into the gap between two tiled windows, the desktop behind it (a screenshot with the cursor):

- **`NSCursor.set()` alone is undone at once**, even after the private
  `CGSSetConnectionProperty(…, "SetsCursorInBackground", true)`: the arrow showed.
- **A window of tylerd's under the pointer that takes mouse events**, with a tracking area
  (`.activeAlways`) setting the cursor on enter and move, plus that private call, shows the resize
  cursor. Whether it works without the private call was not settled (the screen changed under the
  test).

## Window layers

- Normal windows 0, the Dock 20, the menu bar 24 (one per display), status items 25, the desktop and
  wallpaper far below 0.
- **The Dock's window covers its whole display** at layer 20, above every app window. Anything that
  asks for the topmost window under the pointer must skip it.
- **Notification Centre can cover a whole display too** (seen 2026-10-12, macOS 26.7): a window
  named "Notification Center" at layer 21, on screen, exactly the frame of the display with the
  menu bar, above every app window and the Dock's. It wasn't there an hour earlier and appeared
  without anyone opening Notification Centre, probably with a notification, and stayed. Until
  tylerd skipped it, it turned off focus follows mouse and dragging with the modifier on that
  display (found with `tyler debug at`). tylerd now skips every window above the normal layer
  whose frame is a whole display's (`PointerFocus.isOverlay`).
- **While the screen is shared, the cursor is a window** (seen 2026-10-12, macOS 26.7, sharing a
  display in a video call): owner "Window Server", named "Cursor", about 28×40 under the pointer,
  at layer 2147483630 (`kCGCursorWindowLevel`). It is always the topmost window under the pointer,
  so until tylerd skipped it, dragging with the modifier passed every press on to the app, and focus
  follows mouse did nothing, on every display. The window server's privacy indicators
  ("StatusIndicator", the mic and camera dots) sit at the same layer, and the call app's red border
  round the shared display at 2147483631 (`kCGMaximumWindowLevel`), a whole display's frame. Clicks
  go through all of them. tylerd skips every window at the cursor's layer or above.
- Open menus are expected at layer 101 (`kCGPopUpMenuWindowLevel`); not measured.

## Raising without focusing

Measured 2026-10-12 on macOS 26.7, two displays, with a one-off probe (focus window A the way
tylerd does: app frontmost, `AXRaise`, main; then 150 ms later `AXRaise` on window B alone):

- **`AXRaise` alone never puts a window above the focused one.** B goes to the top of its own app's
  windows, and stops there: with A in another app, below all of A's app's windows; with A in the
  same app, just below A.
- **It doesn't move the keyboard focus.** The frontmost app and its focused window stay A's.
- So keeping a window in front of the focused one (a floating layer) can't be done with public
  API: it takes focusing it, or setting its window level (private API, SIP changes).

## Synthetic input (for live checks)

- A synthetic click on a status item only arrives after a mouse move onto it.
- A click posted with `maskControl` leaves later synthetic events with control held, unless a
  control key-up is posted.
- A synthetic Escape doesn't close a status item menu.
- Screen capture needs Screen Recording permission, so what the menu bar looks like needs a person's
  eyes.
