# `tyler start` checks that tylerd can see windows

## Why

After a restart of the Mac, or after logging out and in again, a fresh `tyler start` has been seen
to report success while `tylerd` found no windows at all: nothing tiled, `tyler window list` empty.
The cause was most likely a stale Accessibility entry for the terminal (listed and switched on in
System Settings, but not working). The fix is known (`docs/troubleshooting.md`: stop, remove the
terminal with `−`, add it again, start), but nothing points to it: `start` says
`started tylerd`, and `status` says `tiling on`.

Today `start` only waits until tylerd answers `status`. Only one failure is visible:
`AXIsProcessTrusted()` false shows up as `tiling waiting for Accessibility permission` in
`tyler status`, and `start` doesn't mention it either.

## What we don't know yet

What the failure looked like from inside tylerd. That decides what the probe has to look for:

1. **`AXIsProcessTrusted()` false although the switch is on.** Then tylerd sat in
   `waitingForPermission`, and the only problem is that `start` stays quiet about it.
2. **`AXIsProcessTrusted()` true, but every AX call refused** (`kAXErrorAPIDisabled`, -25211, or
   `cannotComplete`). Then every app failed to attach, gave up after its attempts, and tylerd
   showed `tiling on` with no windows. The log would have had `app observing failed` lines, but
   `AXError` is logged without its code (`register("AXMoved", __C.AXError)`), so they don't say
   which.
3. **The screen was still locked** when tylerd started (measured: AX then reports no windows,
   `devdocs/macos-behaviour.md`). Unlikely when started by hand, but a login item would hit it.

The probe is designed to tell all three apart, so it doesn't matter which it was; what it was gets
recorded in `devdocs/macos-behaviour.md` when it happens again.

## Proposal

tylerd checks its own access to windows, keeps the verdict as part of its permission state, and
reports it in `ServerStatus`. `tyler start` and `tyler restart` wait for the verdict and fail
loudly (exit 1, the reason and the fix) when it is bad; `tyler status` shows it.

### The probe

Facts gathered in TylerPlatform, the verdict decided in TylerCore (`AccessibilityHealth`, a pure
value, unit tested):

- `AXIsProcessTrusted()`.
- One AX read that needs the permission: the system-wide element's focused application. Its
  `AXError` separates "refused" (`apiDisabled`) from "app busy" (`cannotComplete`) and "allowed".
- The cross-check against the symptom: the window server (`CGWindowListCopyWindowInfo`, no
  permission needed; `MacWindowStacking` already reads it) lists the on-screen, layer-0 windows of
  regular apps. If it lists some and AX, once the apps had time to attach, found none of their
  apps' windows, tylerd can't see windows, whatever the first two say.
- Whether the screen is locked (`CGSessionCopyCurrentDictionary`, `CGSSessionScreenIsLocked`).

Verdicts: `ok`, `notTrusted`, `refused` (trusted but AX says no, or sees nothing the window server
shows), `screenLocked`, `pending` (apps still attaching).

## Decisions to make first

| # | Question | Options | Recommendation |
|---|----------|---------|----------------|
| H1 | Where does the probe run? | **a)** In tylerd, reported through `status`. **b)** In the `tyler` client before it spawns tylerd (same terminal, so the same grant). | **a.** The verdict that matters is the running tylerd's, and it can keep checking after start (H3). The client can't see what tylerd attached. |
| H2 | What does `start` do when the verdict is bad? | **a)** Leave tylerd running, exit 1 with the reason and the fix. **b)** Stop tylerd again, exit 1. | **a.** tylerd already waits for a missing permission and starts by itself once it's there; H3 extends that to `refused`. Stopping it would make the user run `start` a second time for nothing. |
| H3 | Is `refused` a permission state like `notTrusted`? | **a)** Yes: tylerd treats "trusted but refused" as no permission (no event taps, no tiling) and keeps probing on the `followPermission` timer, starting once it passes. **b)** No, only reported. | **a.** Safer too: an event tap alive while the grant is broken is the setup that can freeze input (`devdocs/macos-behaviour.md`, "Events and taps"). Whether re-adding the entry makes AX work for a process that is already running is to be measured; if not, the message says `tyler restart`. |
| H4 | How long does `start` wait for a verdict? | Apps attach with retries, so "no windows" is only meaningful after a moment. | Up to **3 s** after tylerd answers, returning as soon as the verdict is `ok` or certain. With no regular app on screen at all, `ok` (nothing to compare). |
| H5 | Locked screen? | Fail, or say and carry on. | **Say and carry on** (exit 0, a note): tylerd finds the windows once the screen is unlocked; it re-reads them then (to check, or a follow-up). |
| H6 | Beyond `start`, `restart`, `status`? | The menu bar item could show a broken grant; `tyler debug` could print the raw facts. | Raw facts in `tyler debug windows` (one line), so a future occurrence can be diagnosed. Menu bar later, if it happens while tylerd runs, not just at start. |

## Increments

Each builds, is tested and documented on its own.

1. **Log `AXError` codes** (done, 2026-10-15): `register("AXMoved", -25211)` instead of `__C.AXError`. Small, and
   useful on its own the next time it happens.
2. **`WindowAccess` in TylerCore** (done): the facts in, the verdict out; unit tests per verdict,
   including "window server shows windows of an app still attaching" (`pending`, not `refused`).
3. **The facts in TylerPlatform**: the probe behind the `AccessibilityGate` port (it grows a
   `probe()`), the window server listing through the existing stacking code, the lock state.
   `FakeAccessibilityGate` returns given facts.
4. **tylerd acts on it** (H3): `WindowManager`'s permission state follows the verdict;
   `ServerStatus` gains an optional `health` (an older tylerd decodes as `nil`, and `start` then
   says nothing). Scenario tests: refused at start, refused then fixed, locked screen.
5. **`start`, `restart` and `status` report it** (H2, H4, H5): `DaemonController` waits for a
   verdict and turns a bad one into a `DaemonError` (exit 1) with the fix; tested with the fake
   `DaemonSystem`.
6. **Docs**: `docs/manual.md` (`start`, `status`), `docs/troubleshooting.md` (the message points
   there), `devdocs/design.md` (the decisions above), `devdocs/testing.md` (a check on real
   windows: start from a terminal with its entry removed, with tylerd stopped first, never while
   it runs), `CLAUDE.md` status. Then delete this plan.

## Measuring, when it happens again

Before fixing a stale entry: `tyler status`, `tyler debug windows`, and `grep -i observing
~/.tyler/tyler.log` (with increment 1, the error codes). Record which of the three cases it was in
`devdocs/macos-behaviour.md`, with the setup described generically.
