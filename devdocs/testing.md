# Testing against real windows

Unit tests cover the logic (`make test`). What only shows on real windows (the AX layer, event
taps, the menu bar, timing) is checked by hand and with `devtools/live-check` (see the `live-check`
skill). This file is the checklist: run the **release** items before every release, and the rest
when the code they name changes.

Escape hatches while checking: `tyler tiling off` brings every window back; `tyler stop` puts
every window where it was before tylerd moved it.

`[x]` means checked at least once on real windows (macOS 26.7, October 2026), `[ ]` never.
Tick an item with the date when it is checked; record what was measured in `macos-behaviour.md`.

## Basics

- [x] After the architecture restructuring (controllers, effects, the reconciler, the module
  split): a restart keeps every window; a workspace switch, a layout change and back give the
  same frames; focus next and back; a three-finger swipe, a swap by drag and a drag with the
  modifier (2026-10-13, built-in display only)

- [x] Windows present at startup tile: one left, the rest stacked on the right
- [x] `window focus`, `window swap`, `layout set`, `layout ratio`, `window float toggle`, `workspace
  retile`, `tiling off` and `on`
- [x] A new window of an app that starts a new process for each window gets the focus, and
  `window swap` moves it (2026-10-14, two terminal windows opened by a shortcut)
- [x] `window swap` animates (`animations.swap`): the two windows slide and resize into each
  other's slots, also master and stack; quick presses in a row (2026-10-14, `tall` with three
  terminal windows)
- [ ] `window float on` and `off`, each pressed twice
- [ ] `window close` on a tiled and a floated window, with tiling off, and in an app that asks to
  save first
- [x] The menu bar and the Dock are left out of the tiled area
- [x] Closing, minimizing and fullscreening a tiled window re-tiles the rest
- [x] `window list` flags: `min`, `full`, `focused`, `floated`; sensible `SLOT` values
- [ ] **release** Opening a new window adds it; quitting an app with several windows removes all
- [ ] **release** A Save panel shows as `dialog` and floats
- [x] An untitled document made while its app is in the background tiles, and an Open panel
  floats (2026-10-14, TextEdit: `make new document` by AppleScript, File > Open)
- [ ] **release** A terminal (character cells) and a window with a minimum size (System Settings)
  end up where expected, and `window list` shows their real frames
- [ ] Moving and resizing a window by hand updates its frame in `window list`
- [ ] `window swap prev`, `layout next`
- [x] `grid` with 4, 5 and 9 windows: the frames of `docs/layouts.md`, gaps included, every window
  on screen (`live-check stacking`); `layout ratio` refuses and moves nothing; a mouse resize on an
  external display (2026-10-12)
- [x] `grid`: resizing with the modifier and focus follows mouse on both displays (2026-10-12; on
  the built-in display only once Notification Centre's overlay was skipped)
- [ ] `grid`: move by drag, the map in the menu bar

## Running tylerd

- [x] `status` warns when the binary is newer; `restart` keeps every window on its workspace and in
  its slot
- [x] `reload` applies gaps; a broken file on `reload` is an error and moves nothing
- [x] `config set gaps.inner 20` re-tiles at once; `config set indicators.map.enabled false` takes
  the map out of the menu bar; `status` lists both; `config reload` and `restart` drop them
  (2026-10-12, two displays)
- [ ] **release** `tyler stop` (SIGTERM) puts every window back, parked ones included
- [ ] **release** `tyler start` survives closing the terminal
- [ ] **release** A broken config file at startup: the error is logged, the defaults apply
- [ ] **release** After `kill -9` with windows parked, the next `tyler start` tiles them again, and
  `tyler stop` then leaves them in view
- [ ] **release** A fresh clone on another user account, following the README word for word
- [ ] The installed `~/.local/bin` build gets every event tap without a new permission prompt
- [x] `tyler start` after a new login reports `access sees the windows`; with the terminal's
  Accessibility switched off, `tyler restart` logs it and fails with the fix (2026-10-15)
- [ ] `tyler start` while the screen is locked (`sleep 10; tyler start`, then lock) waits and tiles
  once unlocked

## Workspaces

- [x] `workspace focus next|prev|<n>` slides and ends with the right windows visible; `next` wraps
- [x] Parked windows stay hidden at the edge after many switches
- [x] `window move-to-workspace` with and without `--follow`
- [x] New windows open on the current workspace
- [x] Switching to an empty workspace leaves no parked window focused
- [x] cmd-tab to a parked window on a second display switches to its workspace
- [ ] **release** cmd-tab to a parked window on a single display switches to its workspace
- [ ] **release** `tiling off` with parked windows leaves a usable screen
- [ ] Closing a window whose app has another window on a parked workspace: does tylerd follow
  macOS's focus there? (`known-issues.md`)
- [ ] Growing and shrinking `[workspaces] count` with `reload`
- [ ] `apps.<app>.workspace`: a new window of an assigned app (app running, and a cold launch) lands on its
  workspace and the view follows; a window opened in the background (`open -g`) stays parked;
  startup with that app frontmost

## Several displays

- [x] Every display tiled with its own row; parked windows stay on their display
- [x] Commands act on the focused display; the menu bar items follow it
- [x] Side by side: each display parks at a free edge, nothing crosses, switches are instant
- [x] Unplugging an external display: every window finds its place
- [x] Dragging a window onto another display, with the preview
- [x] `display focus`, `window move-to-display [--follow]`, `workspace move-to-display`; a pinned
  home survives `restart`
- [ ] A swipe on each display
- [ ] Closing and opening the lid; a long sleep where an external display drops off
- [ ] `displays.<n>.workspaces` in the config
- [ ] Side by side with "Displays have separate Spaces" on
- [ ] Three displays

## Swipes

- [x] A full swipe and a slow swipe switch smoothly; a short swipe goes back
- [ ] Swiping right from workspace 1 wraps to the last
- [ ] 4-finger and vertical swipes do nothing with `fingers = 3`
- [ ] A swipe with a slow app (Firefox) on screen keeps up
- [ ] With a Space or full-screen app to switch to, macOS doesn't also act on the swipe

## Mouse

- [x] Mouse resizing moves the dividers live; `restart` keeps stack heights
- [ ] Move by drag (it replaced the swap): the windows make room at the slot under the pointer and
  the ones in between shift on release, in `tall` and `grid`; a gap keeps the preview; `full`
- [x] Swap by drag of a window an app keeps smaller than its slot (System Settings), dragged by its
  sidebar: preview and swap (2026-10-15)
- [x] The drag preview animates (`animations.drag-preview`): the window slides and resizes into the
  dragged window's slot; sweeping across windows hands each over where it is (2026-10-14, `tall`
  with three terminal windows)
- [x] Focus follows mouse on every display; a quick sweep focuses nothing; a switch with a still
  pointer keeps its focus
- [x] Moving and resizing with the modifier, on a debug build
- [ ] Focus follows mouse: a parked sliver doesn't switch workspaces; open menus stay open; dragging
  a divider; a float over a tiled window; an auto-hidden Dock
- [ ] Gap drag, with `gaps.inner` set: the vertical gap in `tall` moves the ratio, the gap between
  stacked windows their heights, in `grid` too; the focus stays; a click in a gap does nothing; a
  floated window over a gap gets the press; nothing where gaps cross; the resize cursor follows
  the pointer into and out of gaps on every display and Space, goes during a slide and stays on
  the gap during a drag
- [x] The mouse button interceptor is armed only while Option is held or the gap cursor shows, and
  disarmed after (2026-10-15, two displays, the log at `debug`): Option-drag moves, Option-right-drag
  resizes, a gap drag moves the divider, holding Option through several resizes keeps it armed
- [x] Revoking the terminal's Accessibility grant with the interceptor disarmed leaves input
  working, and tylerd logs `permission lost` (2026-10-15, once). With it armed, it is unchecked:
  try that only in a macOS virtual machine, since a freeze needs a forced restart
- [ ] Modifier drag: Option-drag moves, also onto another display; Option-right-drag in each quarter
  of a window in `tall` and the strip; a floated window moves and resizes freely; Option+click and
  Option+right-click still reach the app; Option+double-click; nothing grabbed over the desktop or
  the menu bar; letting go of Option mid-drag; a press during a slide

## Menu bar

- [x] The text item follows workspace switches and layouts; both items' menus work
- [x] A left click on a map thumbnail switches to it; a right click opens the menu
- [ ] The menu's Reload config, Open config (also with no config file) and Quit tyler
- [ ] `tyler config edit`: in a terminal with `$EDITOR` set, the editor runs in place and the config reloads after it; from a hotkey (skhd), the file opens as with Open config
- [x] `[indicators.text]` and `[indicators.map]` `enabled` with `reload` hide and show each item
- [ ] Light and dark menu bars
- [ ] `tiling off` hides the map
- [ ] 10 workspaces fit
- [ ] The map matches `tyler window list` for `tall` with 1–3 windows, `full` and `strip`, and
  follows `workspace focus next`, `window focus next`, `layout ratio` and a mouse resize
- [ ] The menu opened from the map sits under the item

## Strip layout (experimental)

- [x] Switching to the strip, scrolling by focus, swiping, `window size quarter`
- [ ] Windows leaving on the left beside a left Dock
- [ ] A slow app (Firefox) during a scroll and a swipe
- [ ] `restart` keeps the view and the sizes
- [ ] `restart` while the screen is locked: after the unlock, every window is back on its
  workspace and in its place, nothing moves, and `tyler stop` still puts them back
- [x] `restart` while an app is slow to answer (an IDE indexing): its windows come back on their
  own workspaces once it answers (2026-10-14: TextEdit stopped with `kill -STOP` during the
  restart and thawed 1.5 s later; its window, parked on workspace 3, was missing from the list,
  then back on workspace 3 in its slot, unmoved)
- [ ] `quarter` windows against apps' minimum heights
- [ ] A click on a parked window's sliver scrolls to it
- [x] A `full` window after a `half` one shows its first half at the right edge (macOS takes the
  frame as asked), and scrolling to the last window and back by focus parks and brings it back
  (2026-10-12, on an external display above the built-in one)
- [ ] The partly visible window during a swipe, and a click on it scrolling it into view
- [ ] Beside a display on the right, the partly visible window parks instead

## Assumptions in the AX layer

- [ ] The size-position-size sequence in `AXBridge.setFrame` is needed
- [ ] The frontmost-app-plus-raise approach in `AXBridge.raise` works for every app
- [ ] Pressing the close button in `AXBridge.close` closes the window in every app
- [ ] `MacWindowSystem`'s attach retries (6 × 500 ms) are enough for slow-launching apps, and an app that ran out of them is attached when it comes to the front
- [x] A hung app (`kill -STOP <pid>`) with a window in a slide stalls each AX call for 1 s, not about
  6 s: the system-wide messaging timeout reaches window elements (2026-10-14, TextEdit: each
  timeout `AX error -25204` after 1.0 s)
- [x] After a hung app's move times out, switches for the next 5 s don't wait for it (the log says
  `app skipping started`, and the slide lines show no 1 s placement), and its windows move again
  after `kill -CONT <pid>` and 5 s (2026-10-14: with focusing skipped too, the first switch back to
  the frozen app's workspace took 1.01 s, the next ones 0.05 s, every slide 31 even frames;
  again 2026-10-15 with a connection per app: 1.04 s once, then 0.03 s, and placed again after
  the pause)
- [ ] A window closed without a destroyed notification leaves its slot at the next command that
  moves it (an AX call on it fails with `invalidUIElement`)
- [ ] `NSApplication.run()` is needed rather than `dispatchMain()`
