# Floated windows stay visible under focus follows mouse

## Why

With focus follows mouse on, a floated window is easily lost: the pointer leaves it, comes to rest
over the tiled window beside or behind it, and tylerd focuses and raises that window, which then
covers the floated one. Getting it back takes Cmd-Tab or the Window menu.

## What can't be done: keeping floated windows on top

Measured 2026-10-12 on macOS 26.7 (`devdocs/macos-behaviour.md`, "Raising without focusing"): an
`AXRaise` on a window without making its app frontmost moves it to the top of its own app's
windows, but never above the frontmost app's windows, nor above the focused window of its own app.
So tylerd can't raise floated windows again after focusing a tiled one, as i3 and sway keep their
floating layer on top. Raising a window above the focused one needs focusing it (which takes the
keyboard), or setting its window level, which needs private API and SIP changes (yabai's scripting
addition); tyler rules both out.

So the fix is in focus follows mouse itself: it must not be what buries a floated window.

## Proposal

1. **Focus follows mouse never covers a floated window.** When the pointer comes to rest over a
   window, tylerd doesn't focus it if a floated window that is in front of it on screen overlaps
   it: raising it would bury that floated window. A click, Cmd-Tab or a `tyler` command still
   focuses it; those are deliberate. Elsewhere focus follows mouse works as before, also from the
   floated window to a window it doesn't overlap, and onto the floated window itself.
2. **A way back to a buried floated window:** `tyler window focus floating` focuses the floated
   window on the focused display (the next one each time, if there are several). Its own
   increment, after 1.

## Decisions to make first

| # | Question | Recommendation |
|---|----------|----------------|
| F1 | Does the rule in 1 hold always, or only while the floated window has the focus? | **Always.** Only while focused leaves a floated window unprotected once focus went elsewhere by keyboard, and the next rest of the pointer buries it. The cost: a tiled window that a floated one overlaps never gets the focus from the pointer alone; a click gives it. |
| F2 | A setting to turn it off? | No, until someone asks: a floated window is floated so it stays visible. |
| F3 | Is 2 needed for the release? | Yes if a buried window is a common complaint after 1; otherwise later. |

## Design

- `PointerFocus.target` (pure, in `TylerCore`) gets the windows in front of the candidate that
  overlap it, and refuses when one of them is floated. Unit tested with the existing cases plus:
  floated in front and overlapping (refused), floated behind (focused), floated in front but not
  overlapping (focused), the pointer on the floated window itself (focused).
- `WindowStacking` (the protocol over `MacWindowStacking`) answers which on-screen windows are in
  front of a given one, with their frames, from the same window list call as `topmostWindow(at:)`,
  so a rest of the pointer still costs one call. The server fake in `Tests/TylerServerTests`
  follows.
- `WindowManager+FocusFollowsMouse` passes `bookkeeping.floated` in.

## Increments

1. Record the measurement (`devdocs/macos-behaviour.md`) and this plan. **Done.**
2. Rule 1: `PointerFocus` and its tests, then `WindowStacking`, the fake and the server tests.
   Docs: `docs/features.md` (focus follows mouse), `devdocs/design.md`.
3. Check against real windows: a floated window over a tiled one, pointer over each, with
   `live-check stacking`; add the item to `devdocs/testing.md`.
4. If F3 says so: `tyler window focus floating`.
