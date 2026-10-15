# Freeze-safe event taps

## Why

Switching off the terminal's Accessibility grant while tylerd ran froze the Mac: the pointer still
moved, but clicks and keys did nothing, and only a forced restart got out of it. Apple's developer
forums report the same (threads 844416 and 735204, FB24619068, macOS 15 to 27). Revoking
Accessibility from a process that holds an **active** session tap (`.defaultTap`) stops system
input, even when the tap passes every event through and gets no `tapDisabled…` callback.
Listen-only taps are not affected. Apple DTS calls it a bug; there is no documented workaround.
The occurrence here matches the reports, but the revoke was not reproduced.

tylerd's only active tap is `MouseButtonInterceptor`, alive the whole time tylerd runs. Users
can't be expected to recover from another machine through `ssh`: once input has frozen, the way
out is a forced restart. So the work aims at prevention, in layers:

1. **Tell users** not to revoke while tylerd runs.
2. **React to the revoke:** drop every tap the moment permission goes away. This covers switching
   the grant off. Removing the entry with `−` leaves `AXIsProcessTrusted()` true and posts
   nothing, so it isn't covered. Whether dropping the tap brings input back once the freeze has
   begun is unknown.
3. **No active tap at rest:** the tap exists only while a press may be taken over: while a
   gesture is under way, while exactly the modifier is held, or while the pointer is over a
   grabbable gap. Most of the time there is then nothing to freeze on. It also stops every
   ordinary left click from waiting for tylerd's main thread, as the gap check makes it do today.

Detecting a stale grant at start (`AXIsProcessTrusted()` true while every app answers with
itself instead of its windows) is a separate piece of work.

## Increments

1. **Docs.** `docs/troubleshooting.md` and `docs/manual.md`: `tyler stop` before removing,
   re-adding or switching off the grant, and a forced restart if input froze anyway.
   `devdocs/macos-behaviour.md` records the reports, both known-issues files the risk, and
   `CLAUDE.md` says never to suggest changing the grant while tylerd runs.
2. **Drop every tap when permission goes away.** The gate reports the
   `com.apple.accessibility.api` distributed notification as a hint, and `isTrusted` is polled
   every second as a fallback, on the injected clock. On a loss, in this order:
   - `pointer.stop()` (every tap gone);
   - stop observing windows, without restoring them;
   - back to waiting for permission, which `tyler status` and the menu bar item show;
   - `startWhenPermitted` again.
   A scenario test covers the notification and the poll, and granting again.
3. **Spike: arming latency.** A probe with a listen-only `flagsChanged` tap that creates the
   mouse tap when the modifier goes down and invalidates it when it goes up. It measures:
   - the delay before the tap is live, idle and with the main thread busy;
   - whether a click right after the key is still caught;
   - the cost of arming repeatedly, as when typing characters that need the modifier.
   The results go into `devdocs/macos-behaviour.md`. If too many fast presses are missed, rethink
   increment 4 for the modifier (gap arming stays).
   **Done** ("Arming the active tap when the modifier goes down"): the tap is live about 1 ms after
   Option with the main thread idle, and only clicks made within that time are missed. With the
   main thread busy, arming waits for it, and clicks made meanwhile go to the app.
4. **The interceptor armed on demand.**
   - **Decision:** `PressTakeover` in `TylerCore/Pointer/` decides when the tap is needed, and its
     mutators report when that changes. Unit tested.
   - **Platform:** a listen-only `ModifierKeyListener` in TylerPlatform, and a shared
     `ModifierKeys(flags:)`. `MacPointerInput` creates the interceptor only while it is needed
     and invalidates it otherwise (not just disables it). The gesture's own state keeps the tap
     until the button comes up.
   - **Port and server:** a new `PointerInput.gapHovered(_:)`, which `refreshGapCursor()` calls
     when the gap cursor window appears or goes. Scenario tests for it.
5. **Review pass** over the whole diff. Then:
   - the decision goes into `devdocs/design.md`;
   - the known issues narrow to what remains (a revoke while armed, and removing the entry);
   - this plan is deleted.

## Checking

- `make check` for every increment.
- Live check after increment 4:
  - a drag with the modifier moves a window, a right-drag with it resizes;
  - a click with the modifier still reaches the app;
  - a gap drag moves the divider;
  - with the modifier up and the pointer off gaps, the log shows the interceptor disarmed.
- **Never revoke the grant on a Mac in use**: it can take a forced restart. If the revoke itself
  has to be checked, do it in a macOS virtual machine. That is also the only way to learn whether
  increment 2 brings input back after a freeze.
