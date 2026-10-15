# Known issues

Bugs, limitations and things not built, so nobody mistakes them for features. The strip layout's
own issues are in `strip-layout.md`. Remove an item when it is fixed (in the same commit).
`docs/known-issues.md` says the same for users, without the internals: keep the two in step.

## Bugs

- **Revoking Accessibility while the mouse button interceptor is armed can stop all input until
  a forced restart** (reported by others, seen once here; see "Events and taps" in
  `macos-behaviour.md`). Its active tap exists only while `PressTakeover` says a press may be
  tyler's: the modifier held, the pointer over a gap, a gesture under way. tylerd also drops every
  tap when it notices the permission gone (`followPermission`: at the `com.apple.accessibility.api`
  notification, or within a second). Removing the entry goes unnoticed, though, and whether
  dropping the tap brings input back once it has stopped is unknown. The users' docs say to
  `tyler stop` first.
- **An Option-click made before the interceptor is armed goes to the app**: the tap is armed at
  the `flagsChanged` event, on the main thread, about 1 ms after the key when the thread is idle
  but only once it is free when busy (measured; see "Arming the active tap when the modifier goes
  down" in `macos-behaviour.md`). Arming on a thread of its own would close that gap.
- **A Firefox window of a parked workspace was seen on screen at x = 0**, behind the current
  windows, instead of at the left parking spot (displays side by side). Unknown whether Firefox
  refuses the spot (`live-check positions`).
- **Windows of a busy app can go untracked at attach** (unverified): `AXBridge.windows(of:)` gives
  `[]` when the read fails or times out, which looks like an app without windows, and nothing reads
  them again. Seen as possible when tylerd starts while an IDE is indexing; such a window shows up
  only once it gets focus. It can only happen right after the app answered every call of the
  attach (the notifications are registered first, and a failure there retries the whole
  attach). Retry the windows read when it fails rather than returns nothing, but keep the
  observer: an app that never answers the read would otherwise run out of attach attempts and
  not be observed at all.
- **An Option-click can be lost if the mouse button interceptor is turned off mid-press**: the press was already
  swallowed, `MouseButtonInterceptor.turnBackOn` drops it, and the app gets a release without a press. Also,
  a `MouseButtonInterceptor` whose creation failed is kept, so `tyler config reload` never tries to create it again.
- **A minimized window can stay tiled** (seen once, 2026-10-12): a terminal window opened after a
  restart and then minimized was still in tylerd's registry as not minimized, so it kept a slot,
  which showed empty. Minimizing it again fixed it. Not the attribute read (`AXMinimized` is
  already `true` at the notification, see `macos-behaviour.md`), so likely a missed notification,
  or one dropped because `MacWindowSystem.windowInfo` returned `nil` for a failed read (silently). Not
  reproduced with windows minimized right after they open. Log a dropped update, and re-read
  `AXMinimized` of the tiled windows when a sync runs.
- **Finder windows made by AppleScript were tiled, and later listed as `dialog`** (seen once,
  unverified): new ones made the same way were `dialog` from the start. Perhaps the subrole
  changing with the app's activation, as TextEdit's does (`macos-behaviour.md`, Window kinds);
  `WindowKind.classify` now also looks at the title bar's buttons.
- **What a stale Accessibility entry looks like to tylerd is unverified**: after a restart of the
  Mac or a new login, a tylerd once tracked no windows although the terminal was listed and on.
  `tyler start` now catches it (`WindowAccess`), but not which form it took: `AXIsProcessTrusted()`
  false, calls refused although trusted, or calls that work but find no windows. The next time,
  before fixing the entry, note the `access` line of `tyler status` and the error codes of the
  `app observing failed` lines in the log, and record the case in `macos-behaviour.md`. Whether
  re-adding the entry makes Accessibility work for a tylerd already running is unmeasured too.
- **Echo tracking can go stale** (unverified): if an app accepts a focus call but never sends a
  focus event, the window stays on tylerd's list of its own focus calls, and the next real focus
  of it while parked doesn't switch workspaces, once.
- **Focus after closing a window** (unverified): macOS may focus another window of the same app,
  even one on a parked workspace, and tylerd then switches there. If it happens, ignore focus
  events for parked windows right after a window of the same app closes.

## Limitations

- **With the Dock on the left, windows parked at the left edge show a 56-point strip** beside the
  Dock (macOS keeps a window 1 point inside the visible frame, which starts right of the Dock).
  Windows leaving to the left show there briefly during a slide.
- **On a display with a neighbour beside it, switches are instant** (no slide), since nothing may
  cross onto the neighbour.
- **The middle display of three has no free edge.** It parks at the right edge, where its parked
  windows lie on the neighbour.
- **The resize cursor over a gap uses a private window server call** (`SetsCursorInBackground`),
  which a macOS update could take away; the gap would then still resize, without the cursor.
  Whether the call is needed at all, now that a window of tylerd's sets the cursor, isn't settled.
- **Display numbers follow position**, so a different display in the same place gets the same
  workspaces.
- **After a crash or `kill -9`, parked windows stay parked** at the edge of their display (1 point
  visible) until the next `tyler start`, which tiles them again.
- **Native fullscreen windows, windows on other macOS Spaces and apps that aren't regular apps**
  (menu bar apps) are left alone.
- **An unresponsive app stalls tylerd** for the 1 s AX timeout on the main thread once (the final
  placement of a switch, a `tyler` command, the event taps): after a move times out, its windows
  aren't moved or focused for 5 s (its `AppConnection` pauses it), then each call tries again.
  Reads and closing still wait for it every time. The steps of a slide don't wait for it (they go
  to the app's own queue); its windows skip frames.
- **Option+drag inside apps** (Finder's copy, block selection in terminals) is lost while
  `[mouse] modifier` is Option.
- **Terminals and windows with a minimum size** don't fill their slot exactly.

## Not built

- **Starting at login** (`tyler service install`, a LaunchAgent). It needs a stable code signature
  for the Accessibility grant.
- **Float rules** in the config, beyond dialogs and `window float`.
- **Animating snapshots instead of windows** (ScreenCaptureKit): slides between side-by-side
  displays without crossing, and smoother slides with many windows, at the cost of the Screen
  Recording permission and frozen window content during a slide.
- **Signed releases.** `make install SIGN_ID=<identity>` signs with an identity you have; there is
  no project identity.
