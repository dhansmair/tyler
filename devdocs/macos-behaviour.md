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
| Outlook's reminder popup (measured 2026-10-27) | `AXStandardWindow` | no | yes | no |

- **The subrole changes when the app first becomes active**, with no notification tylerd hears, so
  a kind read from the subrole once stays wrong. The buttons are there from the start (read
  0.3 s after the window appeared).
- **The normal windows of the other apps checked** (a terminal, an editor, browsers, Office apps,
  an Electron app) all have close, minimize and full screen buttons and a size that can be set.
  `WindowKind.classify` relies on that. Not measured: windows of apps whose green button only
  zooms (an option of several terminals and editors) presumably lack the full screen button
  while they can be resized, so a missing button alone doesn't make a dialog.

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
  `didWake`.
- **An external display unplugged while the Mac sleeps** (seen three times, 2026-10-24, macOS 26,
  with the screen locked as soon as the Mac sleeps): the displays change at the full wake and
  settle about a second after the display comes on, while the lock screen is still up. Every
  write to a window then answered `invalidUIElement`, and no app listed any window, as the
  locked screen above predicts; after the unlock every window was listed again (#43).
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
  mouse-up without the mouse-down. The callback is told late: in a probe (2026-10-21, macOS 26.7,
  a listen-only `flagsChanged` tap sleeping 1.5 s per event, events posted every 0.5 s),
  `CGEvent.tapIsEnabled` read `false` 2.5 s in, and the `tapDisabledByTimeout` event reached the
  callback about 5 s after that, once the queued events had drained. A tylerd whose callback
  turned its gesture tap back on at that event was found, after a wake from sleep, with the
  gesture tap off and nothing more in the log: swipes stayed dead until a restart. tylerd now
  checks its taps every 2 s with `tapIsEnabled` instead of waiting to be told.
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
  it off does both. Never try it with an active tap in place on a Mac in use. With tylerd's
  interceptor disarmed (no active tap; listen-only taps still in place), revoking the terminal's
  grant left input working, and tylerd noticed and removed its taps (2026-10-15, twice).
- **Arming the active tap when the modifier goes down** (measured 2026-10-15, macOS 26.7, a probe
  with a listen-only `flagsChanged` tap that creates a `.defaultTap` mouse tap when Option alone is
  held and invalidates it otherwise, on the main run loop, and a listen-only mouse tap as the
  reference; nothing swallowed):
  - Creating, adding and enabling the tap costs 0.04 ms (median of 1000; rarely about 30 ms),
    removing it 0.02 ms, so arming at every Option press while typing costs nothing to speak of.
  - Idle main thread: the `flagsChanged` callback runs 0.56 ms after the event (median, max
    1.05 ms) and the tap is live 0.89 ms after it (p90 1.17 ms). 49 of 51 Option-clicks were
    caught. One missed click came 0.87 ms after Option, about as good as pressing both at once.
    The other missed click wasn't armed, for no reason the probe recorded.
  - Main thread blocked 300 ms every 500 ms: the callback waits for the main thread (median 67 ms,
    max 305 ms), and 8 of 24 Option-clicks came before the tap was live and went to the app.
    Every press after the tap was live was caught. With an always-on tap, that busy main thread
    would instead have held every click in the system as long.
  - Option-to-click gaps of quick, deliberate presses: median 106–137 ms, the fastest 5 ms.
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

## tylerd as an app of its own

Measured 2026-10-24 on macOS 26.7, with the release `tylerd` in a hand-made bundle (`Info.plist`
with a bundle ID, `CFBundleExecutable=tylerd`, `LSUIElement`), ad-hoc signed, launched with `open`,
from a terminal that held Accessibility itself:

- **Launched through LaunchServices, tylerd is responsible for itself.** Its parent was launchd, and
  `AXIsProcessTrusted()` said no although the terminal had the grant.
- **The prompt works for an `LSUIElement` app**: `AXIsProcessTrustedWithOptions` with the prompt
  option showed the system's dialog.
- **System Settings lists the app by its file name** (`Tyler.app`), not by `CFBundleName`
  (measured 2026-10-25 with a bundle named "Tyler (development)" in its `Info.plist`, launched
  from the build folder of a checkout, which was listed).
- **From a folder under `/private/tmp` the app got no entry in the list**, although the dialog
  appeared, also after quitting and reopening System Settings. The same bundle in
  `~/Applications` was listed after its prompt.
- **Spotlight finds a real app in `~/Applications`, and nothing else tried** (measured
  2026-10-25, never-launched copies with their own bundle IDs, searched with `mdfind` and
  Spotlight): one under `/opt/homebrew/Cellar/…` wasn't indexed after more than three minutes, nor
  a symlink in `~/Applications` to one in a hidden folder; a Finder alias (a bookmark file) in
  `~/Applications` was, but Spotlight lists it as "alias".
- **The grant follows the bundle ID and the signature, not the path.** The same signed bundle
  copied to another folder and launched from there was trusted at once, so a new install path per
  version (Homebrew's Cellar) costs nothing by itself.
- **A different build in the same bundle is a new identity.** An ad-hoc signature's designated
  requirement is the code's hash (`codesign -d -r-` printed only `cdhash H"…"`): another
  `tylerd` in the bundle, re-signed ad-hoc, wasn't trusted while the switch stayed on.
- **Switching it off and on again doesn't help** (measured 2026-10-25, a probe app that only
  logs `AXIsProcessTrusted()`, two ad-hoc builds in one bundle): after the toggle, the new build
  was still not trusted, launched fresh too, while the old build still was: the entry stays tied
  to the old build's hash. `tccutil reset` (or removing the entry with −) and a new grant made
  the new build trusted on its next launch.
- **`tccutil reset Accessibility <bundle id>` works without `sudo`**, run while no tylerd was
  running. It prints its "Successfully reset" line twice even for one entry. The next launch
  prompted again.
- **`tccutil reset` finds the bundle ID through LaunchServices** (measured 2026-10-25): with the
  app deleted, or rebuilt in place but not yet launched, it failed with `No such bundle
  identifier` (OSStatus -10814) and left the entry in System Settings; after `lsregister -f` on
  the bundle it succeeded. Launching an app registers it. So reset before deleting an app, and
  register a new one before resetting its entry.
- **A grant given while tylerd waits** was picked up by the waiting process within its one-second
  check after the reset; the first time (the very first entry for the bundle ID) it wasn't, and only
  a relaunch made tylerd trusted. Why the two differed isn't known. The probe above, a process
  without a run loop, never picked a grant up while it ran, only on its next launch: that may be
  what a run loop changes, so it says nothing about tylerd. Again on 2026-10-30 (macOS 26.7.2, an
  update between two ad-hoc builds): a first grant was picked up by the waiting tylerd, the grant
  after the update wasn't within a minute, and `tyler restart` of the same build was trusted.
- **No Input Monitoring is needed.** With only the app's Accessibility grant, every tap came up
  (`input` in `tyler status`), and three-finger swipes, dragging and resizing with the modifier,
  and focus follows mouse all worked.
- **Launched with `open`, tylerd's stderr goes nowhere**, so nothing reached `~/.tyler/tyler.log`,
  which `tyler start` fills by redirecting stderr. A bundled tylerd has to open its log itself.

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

## An app's focus across displays

Measured 2026-10-30 on macOS 26.7.2, two displays, with a one-off probe: an Electron editor with a
window A on one display and a window B on the other, B the one it remembers as focused, and
another app in front. Six tries each, the probe's own AX observer and a read on activation.

| Focusing A | B reported on the way | Ends on B |
|---|---|---|
| Frontmost, raise, main, focused (`AXBridge.raise`) | 3 of 6 | 0 |
| Main and focused, frontmost, raise | 6 of 6 | 4 of 6 |
| Raise, main and focused, frontmost last | 6 of 6 | 6 of 6 |
| A posted click on A's title bar | 6 of 6, from the read on activation; no notification | 0 |

- **With both windows on one display, B never showed** after tylerd's calls, in the editor or in a
  plain AppKit app; a posted click showed it once in about five tries in each. So it needs an
  app with windows on two displays, not a parked window.
- **The order of the calls can't avoid it:** frontmost first is the best of the three, and the
  others leave the wrong window focused.
- **A came within 21 ms of B** in every try that ended on A, and 18 ms in a log of tylerd itself.
  `WorkspaceController.parkedFocusSettling` waits longer than that.
- **Not a passing state:** opening a new window (`code -n`) focused a window parked on the other
  display 12 ms later, and closing a window focused the same app's parked window (#12). No focus
  event followed either, so these get past the wait.

Measured 2026-10-30 on macOS 26.7.2, two displays, AppKit fixture apps, three tries each, before
tylerd declined these focuses:

| Case | macOS | tylerd |
|---|---|---|
| Close a window, same app parked on the same display | Focuses the parked window within 1 ms | Switched, 3 of 3 |
| The same, a sibling in view, the parked window used more recently | Focuses the parked window | Switched, 3 of 3 |
| Close a window, same app parked on the other display | Focuses the parked window within 1 ms | Switched, 3 of 3 |
| Quit an app, another app's window parked | Focuses that window | Switched, 3 of 3 |
| Close an app's last window, the app stays | No focus event | No switch, 3 of 3 |

- **The focus can come before the quit reaches tylerd:** 14 to 22 ms before in 2 of 3 fixture
  quits, 41 to 49 ms before in 3 of 3 TextEdit quits. Closes came first in all 12 fixture tries and
  in the one logged on VS Code windows. A quit of VS Code wasn't measured: an isolated instance
  never showed a window.
- **The window server knows of a quit first:** asked with `CGWindowListCopyWindowInfo` when the next
  app's activation arrived, the quitting app's window was already gone in 6 of 6 quits (fixtures
  and TextEdit, 0.2 to 2 ms before the activation). In 3 of 3 controls, with the other app brought
  forward and the window staying, it was on screen. **A close is the other way round:** the window
  server keeps the window for about 265 ms, but `.destroyed` reaches tylerd first. So between them
  the two sources tell at the end of the 60 ms wait, in either order.
- **A sibling on the closing display, the parked window on the other one:** macOS focused the
  sibling, though the parked window was the more recent, in 6 of 6 tries (fixture apps only).
- **Focus can end on the remembered window after tylerd's own focus:** the echo came, the parked
  window's focus 1 ms later, then nothing for 700 ms, so the wait ran out and the display switched
  (#87). Repeatable with two VS Code windows on two displays: swipe the one you were in away, then
  rest the pointer on the other. The remembered window came 23 ms after the request, the wanted one
  1 ms later, and the remembered one again 21 ms after that. AppKit fixture windows on two displays
  didn't do it in 12 tries (macOS 26.7.2, in a separate process, nothing parked).
- **A second focus can land:** in the one case seen with VS Code, focusing the wanted window again
  when the wait ended came back in 6 ms and no other focus followed.

## Synthetic input (for live checks)

- A synthetic click on a status item only arrives after a mouse move onto it.
- A click posted with `maskControl` leaves later synthetic events with control held, unless a
  control key-up is posted.
- A synthetic Escape doesn't close a status item menu.
- Seen 2026-10-26 (macOS 26.7): posted moves onto tylerd's map item, then a posted click or a
  150 ms press, didn't reach it (no switch, nothing logged), while posted clicks reached an app's
  menu in the same session. Clicks on the item stay manual until that is understood.
- On a display with a notch, a status item that doesn't fit beside it is hidden, without notice
  (seen 2026-10-26, macOS 26.7: switching the text item on moved the map behind the notch).
- Screen capture needs Screen Recording permission, so what the menu bar looks like needs a person's
  eyes.

## Not measured yet

Assumptions the Accessibility layer is built on that no measurement has confirmed:

- The size, position, size sequence in `AXBridge.setFrame` is needed (a single position and size
  write may do).
- Making the app frontmost and then raising the window (`AXBridge.raise`) works for every app.
- `MacWindowSystem`'s attach retries (6 × 500 ms) are enough for apps that launch slowly.
- `tylerd` needs `NSApplication.run()` rather than `dispatchMain()`.
