# Testing against real windows

The end-to-end catalogue: what to run on real windows before every release, and after changing
anything the rows touch. The logic behind every row is already covered by a scenario test (the
last column; suites in `Tests/TylerScenarioTests/<Feature>/`, unit tests in their mirrored
folder). A row is here only for what the fakes can't show: what macOS does with tylerd's calls
(`testing-strategy.md`, "Where a test goes"). The catalogue says what to run, not what ran: each
run is written down in `test-runs/` (see "Recording a run"). What a check measured goes into
`macos-behaviour.md`.

## Automated first

Every row is meant to run without a person, in `devtools/e2e`: driven by `tyler` commands,
AppleScript, `open`, posted keys (`live-check key`) and posted mouse events, and checked with
`tyler window list --json`, `tyler debug windows` and `live-check`. A row that needs a person says
`yes` in the **Manual** column; its action says what the person does. Only what can't be posted
or read back is manual: trackpad gestures (macOS has no public way to post them), plugging
displays and the lid, sleep, unlocking the screen, the Accessibility grant, a setting that needs a
logout, what the menu bar looks like (reading it needs Screen Recording), and another user
account.

When a way is found to automate a manual row, its `yes` goes. Until `devtools/e2e` exists, the
automated rows are run by hand too, with `live-check` for what it can read.

**Why** says what only real macOS shows:

| Why | What |
|---|---|
| AX | whether an Accessibility call (a move, a raise, a focus, the close button) does what it says, and the notifications an app sends |
| clamp | where macOS lets a window go: parking at an edge, minimum sizes, character cells, a shorter display |
| tap | whether an event tap sees the event, and what the press lands on |
| timing | a real app's speed: animations, slow and hung apps |
| macOS | what macOS does by itself: focus after a close, cmd-tab, display changes, sleep, Spaces |
| menu bar | what AppKit shows in the menu bar |
| process | the executables, files on disk, permissions, launching |

A row's context is the setup it needs (the heading of its table). A run without that setup (a
second display, the lid) skips the row and says so.

Escape hatches while checking: `tyler tiling off` brings every window back; `tyler stop` puts
every window where it was before tylerd moved it. Act on windows by their id
(`tyler window list`), never on whichever window happens to be focused, and leave windows that
aren't part of the check alone.

## Start and stop

One display, `tall`, a few windows on two workspaces.

| Manual | Id | Action | Expected | Why | Logic in |
|---|---|---|---|---|---|
| | LIFE-START | `tyler start` with windows open | They tile: one on the left, the rest stacked on the right, the menu bar and the Dock left out | AX | WindowEventScenarios |
| | LIFE-DETACH | `tyler start` in a new terminal window, then close that window | tylerd keeps running | process | |
| | LIFE-STOP | `tyler stop` with windows parked on other workspaces | Every window is back where it was before tylerd moved it, parked ones included | AX | RestoreScenarios |
| | LIFE-RESTART | `make build`, `tyler status`, `tyler restart`, with a window floated and a workspace in the strip | `status` warns that the binary is newer; after the restart every window is on its workspace and in its slot, the strip keeps its view and sizes, and nothing moved | AX | RestartScenarios, StripScenarios |
| | LIFE-KILL | `kill -9` tylerd with windows parked, `tyler start`, `tyler stop` | `start` tiles the parked windows again; `stop` then leaves them in view | AX | RestoreScenarios |
| | LIFE-SLOW-APP | `tyler restart` while an app with a parked window is stopped (`kill -STOP`, `kill -CONT` 1.5 s later) | The window is missing from the list, then back on its workspace and in its slot, unmoved | timing | RestartScenarios |
| | LIFE-CONFIG | Start with a broken config file; fix it; change `gaps.inner` in the file and `tyler config reload`; break it again and reload | The start logs the error and uses the defaults; the reload retiles with the new gaps; the broken reload is an error and moves nothing | process | ConfigReloadScenarios |
| | LIFE-CONFIG-EDIT | `tyler config edit` with `$EDITOR` set to a script that changes the file, and without a terminal | The editor runs in place and the config reloads after it; without a terminal, the file opens as with Open config | process | |
| yes | LIFE-LOCKED | `sleep 10; tyler start`, then lock the screen; unlock | tylerd waits, and tiles once unlocked | macOS | WindowAccessScenarios |
| yes | LIFE-LOCKED-RESTART | `sleep 10; tyler restart` with a workspace in the strip, then lock the screen; unlock | Every window is back on its workspace and in its place, nothing moves, and `tyler stop` still puts them back | macOS | RestartScenarios |
| yes | LIFE-PERMISSION | After a new login, `tyler start`; then `tyler stop`, switch the terminal's Accessibility off, `tyler start` | `status` reports `access sees the windows`; without the grant, the start fails with the fix | process | WindowAccessScenarios |
| yes | LIFE-INSTALL | `make install`, `tyler restart` from `~/.local/bin` | Every event tap works (a swipe, focus follows mouse, a modifier drag) without a new permission prompt | process | |
| yes | LIFE-APP | With a code-signing identity: `make install SIGN_ID=<identity>`, `~/.local/bin/tyler start`, turn on `Tyler.app`; then `make install` of a changed build and `tyler restart` | The dialog appears and `Tyler.app` is listed; `start` copies the app into `~/Applications`, and Spotlight finds Tyler; once on, tylerd tiles by itself; the update copies the new build, restarts without a new prompt and nothing moves; every event tap works | process | DaemonControllerAppTests, DaemonControllerInstalledAppTests |
| yes | LIFE-APP-SWITCH | `tyler restart` from a tylerd under the terminal's grant onto `Tyler.app`, and back (`make install` without `SIGN_ID`, `tyler restart`) | Each time the old tylerd puts its windows back first and `restart` says why; the new one tiles once it has its grant | process | DaemonControllerAppTests |
| yes | LIFE-FRESH | A fresh clone on another user account, following the README word for word | It builds, installs, asks for the grant and tiles | process | |

Never switch the grant off while tylerd runs: macOS can then stop all input until a forced
restart (`macos-behaviour.md`, "Events and taps").

## Windows and apps

One display, `tall`.

| Manual | Id | Action | Expected | Why | Logic in |
|---|---|---|---|---|---|
| | WIN-OPEN-QUIT | Open a window; quit an app with several windows | The new window goes in after the focused one; all of the quitting app's windows leave | AX | WindowEventScenarios |
| | WIN-NEW-PROCESS | Open two windows of a terminal that starts a process for each window, by its shortcut (posted keys); `window swap` | The new window has the focus, and the swap moves it | macOS | NewWindowFocusScenarios |
| | WIN-KINDS | TextEdit in the background: `make new document` by AppleScript; File > Open; a Save panel | The document tiles; the Open panel floats; the Save panel shows as `dialog` and floats | AX | WindowEventScenarios |
| | WIN-STATES | Minimize, fullscreen and float a window, then undo each | `window list` flags `min`, `full`, `floated` and `focused`, with sensible `SLOT` values; the rest retile; undoing brings it back | AX | WindowEventScenarios |
| | WIN-MIN-SIZE | Tile System Settings and a terminal | Each ends where expected (System Settings keeps its minimum size, the terminal snaps to its cells), and `window list` shows the real frames | clamp | |
| | WIN-BY-HAND | Move and resize a floated window with the mouse | `window list` shows its new frame | AX | WindowEventScenarios |
| | WIN-CLOSE | `window close` on a tiled and a floated window, with tiling off, and on an edited TextEdit document | Each closes and the rest retile; the edited document asks to save and stays listed until it closes | AX | CloseWindowScenarios |
| | WIN-CLOSE-QUIET | Close the last window of an app that quits with it (Find My), then `window swap` | The closed window's slot goes at that command | AX | |
| | WIN-CLOSE-FOCUS | Close a window whose app has another window on a parked workspace | tylerd stays on the current workspace (#12) | macOS | |
| | WIN-SLOW-LAUNCH | Cold-launch a slow app; bring an app that ran out of attach attempts to the front | Its windows tile; the late one attaches when it comes to the front | timing | |

## `tall`, three windows

One display unless the action says otherwise.

| Manual | Id | Action | Expected | Why | Logic in |
|---|---|---|---|---|---|
| | TALL-COMMANDS | `window focus next\|prev`, `window swap next\|prev\|master`, `layout next`, `layout ratio`, `window float on` and `off` (each twice), `workspace retile`, `tiling off` and `on` | The focus and the raise reach the right window, and the frames are those of `docs/layouts.md` | AX | TilingCommandScenarios |
| | TALL-ANIM | `window swap` between master and stack several times in a row; close a window (`window close` and its close button), minimize one, float one; all again with `animations.swap` and `animations.retile` at `0` | The windows slide and resize into their new slots without dropped frames (the `finished` lines at `info`); at `0` they jump | timing | SwapAnimationScenarios, RetileAnimationScenarios |
| | TALL-FLOAT | `window float on` and `off` on the only window of a workspace, on the right one of two side by side, and on the top right one of three in `tall`; all again with `animations.retile` at `0` | Floated, the window slides 30 points toward the middle, shrinking by 60 points at both ends only along a side it spanned, and no edge lines up with a tiled window; the others slide into place with it; tiled again, it slides back into a slot; at `0` they jump | AX | FloatAnimationScenarios, FloatedFrameTests |
| | TALL-RESIZE | Drag the main window's right edge, and the edge between stacked windows; `tyler restart` | The dividers move live and the dragged window snaps into its slot on release; the restart keeps the stack heights | timing | MouseResizeScenarios |
| | TALL-MOVE-DRAG | Drag a stacked window by its title bar over the others and drop it; sweep across several windows; drop in a gap; drag across the column divider; in `full` | The windows make room at the slot under the pointer, animated; the ones in between shift on release; a gap keeps the preview; the divider moves a window between the sections; in `full` nothing moves | tap | MoveByDragScenarios, DragPreviewAnimationScenarios, MainSectionDragScenarios |
| | TALL-DRAG-SMALL | Drag System Settings, a window its app keeps smaller than its slot, by its sidebar | The preview shows and the drop moves it | tap | MoveByDragScenarios |
| | TALL-MODIFIER | Option-drag a window; Option-right-drag in each quarter of a window, in `tall` and the strip; both on a floated window; Option+click, Option+right-click, Option+double-click; press over the desktop and the menu bar; let go of Option mid-drag; press during a slide | Moves and resizes follow the pointer; a floated window moves and resizes freely; the clicks reach the app; nothing is grabbed over the desktop or the menu bar; the interceptor is armed only while Option is held (the log at `debug`) | tap | ModifierDragScenarios |
| | TALL-GAP | With `gaps.inner` set: drag the vertical gap, the gap between stacked windows, a gap under a floated window, where gaps cross; click in a gap; move the pointer into and out of gaps on every display and Space, during a slide and a drag | The vertical gap moves the ratio, the other gap the heights, the focus stays; the floated window gets its press; nothing where gaps cross; a click does nothing; the resize cursor shows over gaps only, goes during a slide and stays during a drag | tap | GapResizeScenarios, GapCursorScenarios |
| | TALL-FFM | With focus follows mouse on: rest the pointer on each window; sweep quickly across; switch workspaces with the pointer still; rest on a parked sliver, a float over a tiled window, an open menu, an auto-hidden Dock; drag a divider | A rest focuses the window under it; a sweep focuses nothing; a still pointer keeps its focus; a sliver switches no workspace; the float gets the focus; menus stay open | tap | FocusFollowsMouseScenarios |

## `grid`

| Manual | Id | Action | Expected | Why | Logic in |
|---|---|---|---|---|---|
| | GRID-FRAMES | `layout set grid` with 4, 5 and 9 windows | The frames of `docs/layouts.md`, gaps included, every window on screen (`live-check stacking`) | clamp | GridScenarios |
| | GRID-MOUSE | On the built-in and an external display: resize a column edge with the mouse and with the modifier; move a window by drag; focus follows mouse | The grid follows the edge; the windows in between shift on a move; the focus follows | tap | MouseResizeScenarios, MoveByDragScenarios |

## Strip (experimental)

| Manual | Id | Action | Expected | Why | Logic in |
|---|---|---|---|---|---|
| | STRIP-SCROLL | `layout set strip` with more windows than fit; `window focus next` to the end and back; `window size quarter`, `half`, `full` | The view scrolls to the focused window and the rest wait parked; a `full` window after a `half` one shows its first half at the right edge; scrolling back brings every window back | clamp | StripScenarios |
| | STRIP-DOCK | With the Dock on the left, scroll windows out on the left | They park beside the Dock and come back | clamp | StripScenarios |
| | STRIP-QUARTER-MIN | `window size quarter` on System Settings and its neighbour | No window overlaps another; `window list` shows the real frames | clamp | |
| | STRIP-CLICK | Click a parked window's sliver, and the partly visible window | Each scrolls into view | tap | StripScenarios |
| | STRIP-SIDE | Beside a display on the right, scroll windows out | The partly visible window parks instead | clamp | StripScenarios |

## Workspaces

One display, `tall`.

| Manual | Id | Action | Expected | Why | Logic in |
|---|---|---|---|---|---|
| | WS-SWITCH | `workspace focus next\|prev\|<n>` many times, an empty workspace included; `window move-to-workspace` with and without `--follow`; open a window after a switch | Each switch slides and ends with the right windows in view; parked windows stay hidden at the edge; an empty workspace leaves no parked window focused; the new window opens on the current workspace | clamp | WorkspaceSwitchScenarios, WorkspaceAnimationScenarios, MoveToWorkspaceScenarios |
| | WS-CMD-TAB | cmd-tab to the app of a parked window (posted keys) | Its workspace comes into view | macOS | MoveToWorkspaceScenarios |
| | WS-TILING-OFF | `tiling off` with parked windows | Every window is in view and the screen is usable | clamp | WorkspaceSwitchScenarios |
| | WS-APPS | With `apps.<app>.workspace` set: a new window of the app, running and cold-launched; one opened with `open -g`; `tyler restart` with the app frontmost | The window lands on its workspace and the view follows; the background one stays parked; the restart puts the app's windows on its workspace | macOS | AppAssignmentScenarios |

## Swipes

One display.

| Manual | Id | Action | Expected | Why | Logic in |
|---|---|---|---|---|---|
| yes | SWIPE-SWITCH | A full, a slow and a short three-finger swipe; a four-finger and a vertical swipe | The full and slow swipes switch smoothly; the short one goes back; the others do nothing | tap | SwipeScenarios, SwipeRecognizerTests |
| yes | SWIPE-SPACES | Swipe with a Space or a full-screen app to switch to | macOS doesn't also act on the swipe | macOS | |
| yes | SWIPE-STRIP | Swipe across a strip | The windows follow the fingers, the partly visible one too | tap | StripSwipeScenarios |
| yes | SWIPE-SLOW-APP | Swipe, on workspaces and across a strip, with a slow app (Firefox) on screen | The windows keep up with the fingers | timing | |

## Two displays, one above the other

| Manual | Id | Action | Expected | Why | Logic in |
|---|---|---|---|---|---|
| | DISP-TILE | `tyler start`; switch workspaces on each display | Each display has its own row; parked windows stay on their display; commands act on the focused display, and the menu bar items follow it | clamp | DisplayTilingScenarios, FocusedDisplayScenarios |
| | DISP-COMMANDS | `window move-to-display [--follow]`, `workspace move-to-display`, between displays of different heights | The windows arrive in their slots, at the full height of the display they are on | clamp | MoveToDisplayScenarios, MoveWorkspaceToDisplayScenarios |
| | DISP-DRAG | Drag a window onto the other display, by its title bar and with the modifier; across `tall`'s column divider there | The preview shows on the other display, and the drop puts the window there, in the section under the pointer | tap | DragAcrossDisplaysScenarios |
| yes | DISP-SWIPE | Swipe on each display | The display under the pointer switches | tap | SwipeUnderPointerScenarios |
| yes | DISP-UNPLUG | Unplug the external display; plug it back in | Every window finds its place; the external display's workspaces wait parked and come back | macOS | DisplayChangeScenarios |
| yes | DISP-SLEEP-UNPLUG | With the screen locked as the Mac sleeps: unplug the external display while it sleeps, wake it, unlock | Every window is tiled, `tyler debug windows` lists none untracked, and the log has no `window forgetting` lines | macOS | DisplayChangeScenarios |
| yes | DISP-LID | Close and open the lid; a long sleep in which the external display drops off | Every window finds its place | macOS | DisplayChangeScenarios |

## Displays side by side

| Manual | Id | Action | Expected | Why | Logic in |
|---|---|---|---|---|---|
| | SIDE-PARK | Switch workspaces on each display | Each display parks at a free edge, nothing crosses onto the other display, switches are instant | clamp | DisplayTilingScenarios, WorkspaceAnimationScenarios |
| yes | SIDE-SPACES | The same with "Displays have separate Spaces" on | The same | macOS | |
| | SIDE-THREE | The same with three displays | The same | clamp | |

## Menu bar

| Manual | Id | Action | Expected | Why | Logic in |
|---|---|---|---|---|---|
| | BAR-CLICKS | Click a map thumbnail (after a move onto it); right-click the map and pick Reload config, Open config (also with no config file) and Quit tyler; open the text item's menu | The click switches; the menus open under their item and each entry does what it says | menu bar | IndicatorScenarios |
| | BAR-TEXT | Switch workspaces and layouts; `[indicators.text]` and `[indicators.map]` `enabled` with `tyler config reload`; `tiling off` | `live-check menubar` reads the text following each change; each item hides and shows; `tiling off` hides the map | menu bar | IndicatorScenarios, ConfigReloadScenarios |
| yes | BAR-LOOKS | The map for `tall` with 1–3 windows, `full` and the strip, through `window focus next`, `layout ratio` and a mouse resize; 10 workspaces; light and dark menu bars | The map matches `tyler window list` and follows each change; empty workspaces are faint; 10 workspaces fit; it reads in both menu bars | menu bar | WorkspaceMapTests |

## Hung apps

| Manual | Id | Action | Expected | Why | Logic in |
|---|---|---|---|---|---|
| | HUNG-SLIDE | `kill -STOP` an app with a window on a workspace, switch to it and back several times; `kill -CONT`, wait 5 s, switch | Each AX call to it stalls 1 s, not about 6 s; for the next 5 s switches don't wait for it (`app skipping started`, no 1 s placement in the slide lines); after the pause its windows move again | timing | |

## Recording a run

Each release run is written to `devdocs/test-runs/<version>.md` (a run between releases, to
`<date>-<what>.md`):

```markdown
# 0.2.0

- Date: 2026-11-02
- macOS: 26.7
- Build: <commit>
- Displays: the built-in display, an external display above it
- Skipped contexts: displays side by side, three displays

| Id | Result | Notes |
|---|---|---|
| LIFE-START | pass | |
| DISP-LID | fail | #51 |
| SIDE-PARK | skipped | no display beside |
```

Every row of the catalogue appears, as `pass`, `fail` or `skipped`. A failure blocks the release
or links the issue it is known as. Describe the setup in general terms, never the developer's own
(CLAUDE.md, "Nothing about anyone's personal setup").
