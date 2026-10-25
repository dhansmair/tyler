# Design decisions

The decisions that shape tyler, each with its reason. What macOS was measured to do is in
`macos-behaviour.md`; the strip layout's design is in `strip-layout.md`. Add a decision here when
it is made, and change it here when it changes.

## Scope

- **xmonad-style tiling.** Each workspace is an ordered list of windows: a clear prev and next, and
  a main window (the first). Layouts only decide where each slot goes, so a new layout is a new
  type, not a new model.
- **Workspaces side by side in a row, like pages**, one row per display. Moving between them slides
  and snaps.
- **Server plus CLI.** `tylerd` owns all window state; `tyler` sends one command and prints the
  reply. **No hotkeys in tylerd**: skhd, Karabiner-Elements or Raycast bind keys to `tyler`
  commands, so tylerd needs no keyboard access and users keep their key tool.
- **Accessibility API only.** No private WindowServer API, no scripting additions, so SIP stays on.
  The price: tylerd can't hide a window or move it across Spaces, and every move is one AX call per
  window.

## Architecture

- **The target architecture** (an input, intent, update, effects loop over a pure core, desired
  frames reconciled with what macOS reports, TylerCore's bounded contexts) is in
  `architecture.md`. Chosen over classic MVC because the "view" is other apps' windows, which
  tyler can only ask to move and which answer back.
- **Design principles** (feature slices, one owner per piece of state, deciding apart from doing,
  dependencies pointing one way) are in `CLAUDE.md`; this section records the decisions taken
  under them.
- **A target for the running program, folders for the domain.** Logging, the paths of tyler's
  files and the version are in `TylerRuntime`, which `TylerCore` doesn't depend on: the compiler
  keeps the pure core from logging or touching files, the rule worth a target. Windows, displays
  and geometry are the domain's shared vocabulary and live in `TylerCore` as its bottom context,
  kept apart by a SwiftLint rule like the contexts above them. They were once a `TylerFoundation`
  target holding both, which no target used without `TylerCore`, under a name that said neither.
- **Thin executables.** Logic lives in libraries; everything that touches macOS (AX, NSScreen,
  event taps, timers) sits behind a protocol so tests use fakes. `TylerPlatform` is the only
  untested layer and stays thin.
- **One actor owns the state.** `WindowManager` is `@MainActor`. GCD is used only in `IPCServer`
  (blocking socket I/O), for `tylerd`'s signal sources and in `AppWriteQueue`;
  `IPCServer.runBlocking` is the single bridge into async code. Its cost: anything that blocks the
  main thread (an AX call to a busy app, up to the 1 s messaging timeout) also stalls every `tyler`
  command.
- **The steps of a slide, swipe or move don't wait for the apps.** `setPosition` and
  `setFrameStep` hand each step to a serial queue per app (each `AppConnection`'s `AppWriteQueue`), which
  writes only the newest step of each window: the windows of a frame move side by side, a slow app skips frames instead of
  holding up the others, and the main thread stays free for input. Everything else (a full
  `setFrame`, focusing, reads) stays on the main thread, and a `setFrame` first waits for the
  window's app's queue, so a final placement always lands after the last step.
- **The window system talks to each app through a connection of its own.** `MacWindowSystem`
  knows every app: which run, attaching and retrying, which window is in which app, and the
  focused window across them. An `AppConnection` knows one app: its windows, reading them, its
  notifications, its step queue, moving, focusing and closing, and whether it answers. It reports
  to a closure and never learns about workspaces, layouts or other apps. Before, one 400-line
  class joined six helpers by process ID, and following one app meant joining them in your head.
- **Accessibility and `NSWorkspace` sit behind dumb seams.** `AXClient` and `WorkspaceClient`
  forward one to one to the C Accessibility API and to `NSWorkspace`, with no tyler logic, so
  everything above them (`AXBridge` included) is unit tested against `FakeAXClient`, a small AX
  emulator, and `FakeWorkspaceClient`. The window system holds `any AXClient`, an existential on
  the path of every step: each call is a round trip to an app that takes milliseconds, so the
  dispatch is noise.
- **Types are named after their responsibility, not their technology.** Only the lowest layer,
  whose responsibility is a technology, is named after it (`AXBridge`, `AXClient`). A port's real
  implementation is `Mac<Port>` and its fake `Fake<Port>`; the ports are in `TylerServer/Ports/`,
  and TylerPlatform has a folder per port. "Backend" said nothing about what was behind it.
- **One place moves and focuses windows** (`WindowMover`). It remembers what moving needs: each
  window's frame before tylerd first moved it, the windows on their way to another display, and
  the focus events that are tylerd's own echo. A window the user grabs with the modifier goes
  through it too (`carry`), but isn't remembered as tylerd's move, so `stop` doesn't undo the
  user's own drag. The rest of the per-window state (`WindowBookkeeping`) stays with the manager,
  which forgets a closed window in both at once.
- **IPC:** one newline-delimited JSON request and one response per connection over a Unix socket,
  `~/.tyler/tyler.sock` (`TYLER_SOCKET` overrides it). A server that can't decode a request answers
  that it is probably older than the client.
- **Commands are defined once**, in the command table in `TylerClient/CommandLineParser.swift`, which
  builds the usage text and the parsing; a test checks that `docs/manual.md` has a heading for each.
  Commands are grouped by what they act on, `tyler <noun> <verb>` (`window focus next`,
  `workspace move-to-display 2`): the first word is the thing that changes, so where a new command
  goes isn't a judgement call, and `tyler window` alone can list what a window can do. Commands
  about tylerd itself (`start`, `stop`, `restart`, `status`, `ping`) and the global `tiling` mode
  stay at the top; reading and changing settings is `config get|set|reload`. One spelling per action, no aliases. The CLI and wire format say
  `master` (the xmonad word); Swift code says `main`
  (SwiftLint's `inclusive_language`).
- **The animation has a clock.** `Animator` is a struct with an injected `Clock` (the test seam):
  250 ms, frames on an 8 ms grid, progress from elapsed time, so a slow app makes a slide coarser
  but not longer. A snap is an animation with zero steps.
- **Each animation other than the slide has its own duration** in `[animations]` (`swap`,
  `drag-preview`, `retile`), carried by its `Transition` or effect; 0 makes it a snap through the same code, with no "animations on" switch.
  A swap runs as a slide (a command mid-swap jumps it to its end). A swapped window changes size
  along the way, in step with its position: resizing only at the ends (shrink, move, grow) looked
  odd. A resize makes the app lay out again (18–23 ms a write), so these steps go through the
  per-app queues like a slide's moves (`setFrameStep`): a slow app skips frames instead of holding
  up the main thread, and the 250 ms default leaves enough frames to look smooth.
- **A window leaving re-tiles the others with an animation, a window arriving doesn't.** When
  the sync after a window event finds that the focused workspace only lost windows, the others
  go from the slots they had before the sync to their new ones as in a swap (`animations.retile`).
  They start from those slots, not from the frames macOS reported: those lag behind the events,
  and a window leaving mid-animation would start the next one from a frame on the way. A window
  arriving has no slot to come from, so the others jump, and in a scrolling layout the view
  moves, so they jump there too.
- **Slide, swipe and drag are one state** (`Interaction`): they never happen at the same time. A
  command that arrives mid-slide first jumps to the slide's end; one that arrives mid-swipe or
  mid-drag puts the windows back.
- **One type per file, and tests that mirror the sources.** Each type is in a file named after
  it, and its tests in `<Type>Tests.swift` or `<Type>Tests+<Aspect>.swift` at the mirrored path,
  so a type and its tests are found by file name alone, by people and agents, and small files
  conflict less when two agents work at once. The folder, not a shared file, groups a family of
  types; a private helper type is nested in its user, so it stays private. Scenario tests are
  named after the behaviour instead, in the folder of their feature (see Testing). SwiftLint and
  `devtools/check-test-paths` keep it so.

## Terminology

*Display* is a physical screen. *Workspace* is one page of a display's row (`WorkspaceRow`), with
its own list, layout and ratio. *Stack* means only the windows beside the main window in `tall`.
*Monitor* isn't used (except for AppKit's event monitor API), and *space* is avoided (macOS
Spaces). `docs/manual.md` (Concepts) defines the user-facing terms.

## Tiling

- **New windows tile.** Dialogs and sheets float; `window float` switches any window. A new window
  goes after the focused one; windows present at startup are ordered left to right. What is a
  dialog comes from the subrole and the title bar together: a window with a full screen button
  is a document, one without a close or minimize button isn't, since the subrole alone misleads
  both ways (`macos-behaviour.md`, Window kinds).
- **Tiling reacts to commands and to windows appearing, disappearing or becoming un/tileable**
  (minimized, fullscreen), not to every move. A move by hand is handled as a mouse resize or a
  move by drag, otherwise the window snaps back on release.
- **Only regular apps** (`activationPolicy == .regular`) and windows on the current Space are
  tracked; native fullscreen windows are left alone.
- **`tiling off`** brings every parked window back and keeps the current workspace's list, so
  `tiling on` restores its order.
- **Restore on exit.** SIGINT and SIGTERM put every window tylerd moved back to its *original
  frame*: the frame just before tylerd first moved it. Windows tylerd never moved are left alone. A
  crash or `kill -9` skips this. The next tylerd tiles the windows it finds parked, and remembers
  each one's original frame pulled sideways into view (`Parking.isParked`, `Parking.pulledIn`),
  so `stop` and `tiling off` don't send them back to the parking spot.
- **Layouts** implement `Layout`: a pure function from the workspace's windows (in list order),
  the layout's own `State`, the area and `LayoutGaps` to frames, and from a mouse resize to a new
  state. Each layout's state has a type of its own (`TallLayoutState`, `GridLayoutState`, ...),
  and a workspace keeps all of them in `LayoutStates`, one field per layout, so a layout's state
  survives switching away and back. A closed struct rather than a dictionary: every layout lives
  in this repository, and the compiler asks for the field when a layout is added.
  `LayoutKind.bound` binds each layout to its field with a key path: the one switch that
  dispatches. Each layout lives in a folder of its own under `Sources/TylerCore/Layouts/`.
- **State kept per window** (the strip's sizes) follows the window, not its slot: a state is
  keyed by `WindowID` and implements `LayoutState`'s two hooks, `remove(_:from:)` when a window
  leaves the list (a `quarter`'s column mate goes back to `half`) and `adopt(_:from:)` when it
  arrives from another workspace. So nothing outside the layout knows about it.
- **Commands for one layout** (`layout ratio`, `window size`) change that layout's state through
  `Workspace.update(_:_:)`, which refits the view after, whichever layout is active: a strip size
  set in `tall` waits for the strip. What the user is told stays in the server (the grid refusing
  a ratio, "used by the strip layout").
- **`tall`'s master section is a count over the list**, as xmonad's `nmaster`: the first
  `mainCount` windows (`TallLayoutState`, 1 by default) are stacked in the left column. A
  workspace stays one ordered list, so `focus`, `swap` and the other layouts are unchanged, and
  `window promote` and `demote` are a move in the list plus one more or one fewer. An extension
  of `tall` rather than a second layout: that would have duplicated the layout, its resizing and
  its docs for one number, and `mainCount` 1 is exactly the old `tall`. The count follows the
  windows, unlike xmonad's: a closing master takes its place with it (`remove(_:from:)`), at
  least one window stays a master, and new windows open in the stack, so the section only
  changes when the user changes it. The cost of a count: reordering the list in another layout
  changes which windows are masters back in `tall`.
- **A layout that scrolls** adopts `ScrollingLayout` (only the strip). The workspace owns the view,
  as it owns focus, and stores it as the window at its left edge rather than in points, so it
  survives display and gap changes. The layout answers where the view can rest, how it fits the
  focused window, and where a scroll lands, so the workspace and the server know nothing about
  columns. Layouts that don't scroll leave the view alone; switching to a scrolling layout fits
  it to the focused window. The frames depend on the view, not just shift with it: columns
  wholly out of view must lie wholly off the area.
- **The strip's columns follow each other without gaps**, and a window partly in view shows the
  part that fits (`DisplayInfo.shows`: any of it on the display). At an edge with a neighbouring
  display such a window parks instead, since nothing reaches onto another display.
- **`tall` and `grid` share `ColumnLayout`** ("columns of rows"), which also does mouse resizing.
  It takes the slots' sizes in as `ColumnWeights` and gives them back after a resize; each layout
  keeps its own (`tall`: the master ratio and its row weights).
- **`grid`** fills columns two windows high, up to four columns, then three high and so on
  (`GridLayout.rowCounts`). Up to three windows it is `tall`'s shape. When the windows don't fill
  every column, the first column holds the leftover, so the master stands alone with an odd count
  and gets the most room. Four columns at most, because a fifth on a laptop display is under 300
  points wide. It has no master ratio: at four or six windows no column is the master's. Its
  column and row weights (`GridLayoutState`) are its own, not `tall`'s: a row slot means
  different windows in the two layouts, so a drag in one would show up oddly in the other. On a
  portrait display it is still columns: turning column layouts into rows there is a decision for
  `tall` and `grid` together. It is in the default cycle, between `tall` and `full`, although up
  to three windows `layout next` from `tall` then seems to do nothing: that costs one more key
  press, and leaving it out hid a layout that suits more windows than `tall` does.
  The ratio is clamped to 0.1…0.9.

## Workspaces and parking

- **Parking.** A window of an inactive workspace sits just past an edge of its display, at its own
  height, with 1 point inside the visible frame (macOS pulls it back if it is further out; see
  `macos-behaviour.md`). The edge is the right one, or the left one if only the right side has a
  neighbouring display (`DisplayArrangement`).
- **The slide is horizontal**, because macOS won't let a window leave through the top or bottom.
  `next` moves the current windows out to the left while the next workspace's come in from the
  right. Every window moves by the same offset, its x kept within `Parking.allowedX`.
  `move-to-workspace` without `--follow` slides only the moved window out, towards its workspace.
- **Nothing slides onto another display.** On a display with a neighbour beside it, switches are
  instant. Making only the windows that would cross jump was tried and looked worse than switching
  instantly.
- **Focus.** Focusing a parked window (cmd-tab, a click on the Dock) switches to its workspace.
  tylerd ignores the focus events its own focus calls cause, so a quick `next`, `prev` doesn't
  switch back late. On an empty workspace tylerd makes itself frontmost, so keys never go to a
  parked window. A floated window keeps the focus.
- **Floated windows and dialogs** belong to no workspace and stay visible everywhere.
- **A floated window moves out of its slot** (`FloatedFrame`), sliding there with the windows
  that take its place (`animations.retile`). Left in its slot it sat flush with the tiled windows
  and didn't look floated. On each axis the slot doesn't span, it moves 30 points toward the
  middle of the tiling area and keeps its size; on an axis the slot spans it can't move without
  leaving the area, so it shrinks by 60 points at both ends instead. A window shrinks only where it
  has to: shrinking on every side looked wrong for a window beside another. Tiling it again
  slides it back the same way. In the strip it stays where it is, as the strip's windows jump when
  the list changes.
- `prev` and `next` wrap; numbers are 1-based and range-checked.

## Several displays

- **Workspace numbers are global.** Each workspace belongs to one display; a display's row is its
  workspaces sorted by number. `workspace 5` switches on the display that holds 5; `prev` and `next`
  stay in the focused display's row. `apps.<app>.workspace` uses the global numbers.
- **`displays.<n>.workspaces`** lists a display's workspaces; a display without a list gets
  `workspaces.count`, numbered on from the previous display.
- **Display numbers**: the one with the menu bar is 1, the others follow left to right, then top
  to bottom. Displays are recognised by UUID (`DisplayKey`), which survives replugging, clamshell
  mode and reboots.
- **Commands and the menu bar act on the focused display; swipes on the display under the
  pointer.** Each display's menu bar can't show different content through public API (the other
  copy is a replicant), so the items show the focused display's row.
- **Displays that come and go.** tylerd acts 1 s after the last screen-parameters notification.
  Until then the lists hold still. A display's workspaces join display 1 when it goes away and go
  home when it returns: home is the configured display, or the one `move-workspace-to-display`
  pinned. Then every window is placed again, parked ones included, since macOS moves them.
  Before that, every observed app's windows are read again: a window tylerd stopped tracking
  while it stayed open joins as a new window (on the current workspace of its display), since
  nothing else would find it before an event names it.
- **Displays that settle at the lock screen wait for the unlock.** A wake that changes the
  displays settles them while the screen is still locked, when macOS shows no windows (#43).
  tylerd looks again every second and places the windows once the screen is unlocked.
- **A write that says the window is invalid forgets it, unless the screen is locked**: then every
  window answers so, and none closed.
- **Moving windows between displays.** A window dragged onto another display takes the slot under
  the pointer, with a preview. One that changes display any other way goes last in that display's
  current workspace. tylerd notes each window it sends to another display and holds it on its
  workspace until the move is reported, so several moves at once don't pull windows apart.

## Mouse and trackpad

- **Mouse resizing** moves the layout's dividers live, throttled (`[mouse] follow-interval`, 16 ms)
  because every resize makes the app lay out again. The interval counts from the end of a step, not
  its start: the moves echo back as notifications to read, and the dragged window's own updates,
  which drive the drag, wait behind them (measured: `devdocs/macos-behaviour.md`, Speed). While a resize is in progress
  the neighbours get two writes without a read back (`FrameWrite.inPassing`); the drop settles
  them. Stack heights are kept per slot.
- **Move by drag**, not swap: the dragged window goes in at the place in the list whose slot is
  under the pointer (`Workspace.dropPlace`, the same rule as an arrival from another display), and
  the windows in between shift by one. A swap moved a window the user never touched to the far
  end of the layout; making room keeps the others in order, and is what a drop onto another
  display already did. The window's own place is tried first, so over its own slot (in `full`,
  everywhere) nothing moves. Previewed live; a drop in a gap keeps what the preview shows, one
  outside the visible area or over its own slot snaps back. The dragged window keeps its size
  during the preview (resizing it without animation felt awkward, and animating it would
  re-layout the app every frame). The windows the preview moves slide there, resizing on the way
  (`animations.drag-preview`). The animation belongs to the drag (`DragPreview`), not the slide,
  so the drag goes on; a new place takes each window over from the frame it was last given.
  Ending the drag places the preview's finals first, then puts the moved windows back whatever
  the registry says: queued steps are reported back late, so the registry can't tell where a
  window the preview moved is.
- **Moving and resizing with a modifier** (Option by default): an active event tap holds back the
  mouse-down; past 4 points it becomes tyler's move or resize and the rest of the gesture is
  swallowed, otherwise the held click is posted again so it reaches the app. The tap runs on the
  main thread like the other taps; if macOS turns it off for being slow, tylerd turns it back on
  and drops the held press. A tap on its own thread is the fallback if that happens in practice.
- **The active tap exists only while a press may be tyler's** (`PressTakeover`): while exactly the
  modifier is held (a listen-only `flagsChanged` tap tells), while the gap cursor shows, and until
  a gesture's button comes up. Removing the Accessibility grant from a process with an active tap
  in place can stop all input until a forced restart (reported, seen once), and listen-only taps
  are not affected; most of the time there is now no active tap to freeze on, and ordinary clicks
  don't wait for tylerd's main thread. Arming costs 0.04 ms and is live about 1 ms after the key
  (measured); a modifier-click made before then, or while the main thread is busy, goes to the
  app. Arming on a thread of its own would close that gap, if it shows in daily use. The tap is
  invalidated, not just disabled, since whether a disabled active tap is safe is unknown.
- **tylerd follows the Accessibility permission for as long as it runs**, not only until it is
  first granted: at the `com.apple.accessibility.api` notification and every second, and once it
  is gone it hands over to itself (every tap and observer goes, the windows stay where they are)
  and carries on with the workspaces when it is back. Removing the entry from the list posts
  nothing and leaves `AXIsProcessTrusted()` true, so only the docs (`tyler stop` first) guard that.
- **Resizing by dragging a gap** goes through the same active tap: a left press with no keys is held
  when `GapGrab` finds it between two slots in view and the window server has nothing in front of
  it there, and a drag then resizes the window before the gap (its right or bottom edge) through
  the layout, as a resize with the modifier does. The tap is armed only while the gap cursor shows,
  the same decision as the press's, so other clicks never reach tylerd. Not chosen: invisible windows in the gaps (a
  window per gap per display, kept in step with every layout change, slide and swipe, and stacked
  above the desktop but below every other window, which macOS can't promise across apps), or one
  window behind all others (it would take every click on the desktop). Neither shows a resize
  cursor for sure either: an app in the background may not be able to set it.
- **The gap under the pointer shows the resize cursor**, set by an empty window of tylerd's over
  the gap, at the normal level (another app's window brought over the gap covers it). It follows
  the pointer's moves, which are watched while `mouse.gap-resize` is on, and is checked again
  after anything that moves windows and when a slide, swipe or drag starts or ends (hidden
  meanwhile; during a gap drag it follows the gap, so the cursor stays). The window list is read
  only when the pointer comes to another gap. The window server's stacking leaves tylerd's own
  windows out, or that window would be in front of the gap it marks. The cursor needs the window
  to take mouse events (so a click in a gap lands on it, not the desktop) and the private
  `SetsCursorInBackground` call; `NSCursor.set()` alone, from the background, is undone at once
  (see `macos-behaviour.md`). A white bar drawn in the gap was tried first and dropped: the
  cursor alone says enough.
- **Focus follows mouse** (off by default): focus and raise the window the pointer comes to rest
  over, through the same call as `tyler window focus`. Only pointer movement triggers it, so a keyboard
  focus is never undone by a still pointer; only windows in view count, and only inside a display's
  visible frame. No pointer warping.
- **Swipes**: a listen-only gesture tap feeds a `SwipeRecognizer` (touches to an offset, locked
  sideways), a `OneEuroFilter` smooths it, the windows follow the fingers, and on release `Snap`
  picks the neighbour or the way back. The swipe's target is an enum (`SwipeTarget`): the workspace row
  or a scrolling layout's view. `SwipeSession` (TylerCore) decides each step and the ending as
  values (`SwipeStep`, `SwipeEnding`); the server only paces the steps and carries them out, so the
  swipe is unit tested without a manager. A drag works the same way: `DragSession` decides what
  the preview moves and what a drop does (`DragDrop`), and `+Drag` carries it out.

## Menu bar

- **Indicators get a snapshot.** The server hands every menu bar item an `IndicatorSnapshot`
  through the `Indicator` protocol whenever it changes; the items live in `TylerIndicators` and
  redraw only when what they show changed. Menu items send ordinary `Request`s, so the menu behaves
  exactly like the CLI.
- **The workspace map** fills the status item's height; the current workspace is bright and the
  others dimmed, the focused window light blue. Each window shows its app's icon, or an SF Symbol
  or Nerd Font glyph from `apps.<app>.icon` (app icons are too detailed at this size).

## Configuration and running

- **`~/.config/tyler/tyler.toml`**, optional (`TYLER_CONFIG` overrides it). A small built-in TOML
  parser supports what the config needs and rejects the rest with an error; no dependency. Unknown
  keys are errors. A broken file at startup logs the error and uses the defaults; a broken file on
  `config reload` is an error and keeps the current settings.
- **`tyler config set` lasts for the running tylerd only.** It is for trying a setting out; the
  file stays the one place settings are kept, so `config reload`, `stop` and `restart` drop what
  `set` changed (the handed-over state holds no config). `set` changes the key in the config's
  TOML document and parses the whole document again, rather than running the one setting's
  reader, so the checks between settings (an app's workspace against the displays' lists) and the
  error messages are exactly the file's. A word without quotes is a string, so
  `layouts.default tall` needs no shell quoting. `tyler status` lists what `set` changed.
- **`tyler config edit` edits in the terminal it runs in, or asks tylerd.** A terminal editor
  (`$VISUAL`, `$EDITOR`) needs a terminal, which only the client has, so in one the client runs it
  in the foreground on the file tylerd reads (from `status`) and reloads after. From a hotkey there
  is no terminal, so the client sends `configEdit` and tylerd opens the file as the menu's Open
  config does; the menu sends the same request, so the two can't drift apart. Opening an editor is
  platform code, so tylerd hands it to `CommandRouter` as a closure rather than TylerServer
  reaching for it.
- **One rule for where a setting goes.** Feature sections hold global settings (`[gaps]`,
  `[mouse]`, one section per menu bar item under `[indicators]`); tables keyed by a thing hold the
  settings of that thing (`[apps."<app>"]`, `[displays.<n>]`). So every setting has one dotted
  path (`indicators.map.enabled`), which the file, the manual and `tyler config get|set` share,
  and a new setting for one item, app or display has an obvious home.
- **`tyler start`** spawns the `tylerd` next to `tyler`, detached, with its output in
  `~/.tyler/tyler.log`. The terminal stays the process responsible for Accessibility, so rebuilds
  need no new grant. A LaunchAgent would need its own grant and a stable code signature, so
  `service install` is left for later. Started by LaunchServices (`open`, a login item), tylerd's
  output goes to /dev/null, so then tylerd opens the log itself (`LogFile`); a terminal or a pipe
  keeps its output.
- **`tyler start` checks that tylerd can reach the windows** (`WindowAccess`). A grant can look
  fine and not work: after a restart of the Mac or a new login, a stale entry left tylerd
  tracking no windows while `status` said `tiling on`. Before tracking, tylerd needs
  `AXIsProcessTrusted()`, an unlocked screen, and one Accessibility read (the focused app,
  through the system-wide element) that macOS doesn't refuse; until then it waits, as for a
  missing permission, and starts on its own once all three hold, so no event tap is alive while
  the grant is broken. Once tracking, it compares its windows with the window server's
  (`CGWindowListCopyWindowInfo`, which needs no permission): seeing none of the on-screen windows
  of regular apps is reported, not acted on, since stopping would only start again at the next
  check. `status` carries the verdict; `start` and `restart` wait for apps still being retried
  (up to 4 s) and exit 1 with the fix for a verdict that needs one, leaving tylerd running. A
  locked screen is a note: tylerd starts once it is unlocked. The check runs in tylerd, not in
  the client before it spawns tylerd: what matters is what the running tylerd sees.
- **`tyler restart` keeps windows in place**: tylerd writes its workspaces to
  `~/.tyler/tyler.state.json` (version 3: a row per display, and each workspace's `LayoutStates`
  as one value, so a new layout or a new piece of layout state needs no change to the file's
  format) and exits without moving anything; the next one matches windows by `CGWindowID` and
  carries on. A window not there yet (its app answers late, or the screen is locked and macOS
  shows no windows) gets its workspace, its place in the order, its float and its original frame
  back when it appears (`LateHandOver`), if it is the same app's: the file names each window's
  process ID, which a restart doesn't change. A file more than a minute old was left behind and
  is ignored and removed (window IDs are reused after a reboot or a new login). `status` warns
  when the binary on disk is newer than the running one.

## Testing

- **Three layers, a pyramid** (`testing-strategy.md`): unit tests for one decision, scenario tests
  for the whole server on fakes, and an end-to-end catalogue on real windows. Each has its own
  place and command (`make test-unit`, `make test-scenario`), and a test goes at the lowest layer
  where its bug could show. Before the split, about 400 tests of the whole server sat among the
  unit tests, named after controllers, and nothing said which kind a test was.
- **A scenario reads as context, input, what the user sees.** `Scenario` places windows on
  workspaces directly instead of replaying commands, gives one input in the words of `docs/`, and
  reads lists, frames and focus. It never calls into the manager or a controller, so the inside
  can be restructured without touching it. Scenario tests sit in `TylerScenarioTests/<Feature>/`,
  named after the behaviour, since a behaviour crosses controllers.
- **Expected values don't come from the code under test**: a frame is a literal or a region worked
  out from the display, never the layout's own result. No golden files.
- **The end-to-end catalogue says what to run, not what ran.** A tick that something worked once
  protects no release, so the catalogue has ids and no ticks, and each run is kept in
  `test-runs/`. A row is there only for what macOS decides; its logic has a scenario test.
- **Automate as much as possible.** A manual check is skipped when time is short and judged
  differently each time, so a row needs a person only when macOS gives no way to post its input
  or read its result back.
- **End-to-end runs belong in a macOS virtual machine.** Only the socket keeps a second tylerd out,
  so a test tylerd beside the developer's would tile the same windows, and rows that stop tylerd
  or turn tiling off act on every window on screen. In a VM nothing reaches the machine in use,
  and switching the Accessibility grant off can't freeze it. Not built yet.

## Releases

- **MIT license**: short, permissive, and usual for macOS tools.
- **SemVer, from `0.1.0`** (tag `v<version>`). Before 1.0 a minor version may change the CLI,
  the config file and the wire format, and `CHANGELOG.md` says how. One constant, `TylerVersion`
  in `TylerRuntime`, holds the version.
- **Releases ship as source**, installed with `make install`. A prebuilt binary needs a Developer
  ID and notarization to get past Gatekeeper, and an unsigned or ad-hoc-signed one loses its
  Accessibility grant on every update. A Homebrew tap is the next step.
- **The history was squashed before the repository went public**: it named the developer's own
  setup in commit messages and old devdocs. The rule against that is in `CLAUDE.md`.
- **`CLAUDE.md`, `.claude/` and `devtools/` are published**: they are the honest record of how
  tyler is built.
- **Open issues are GitHub issues**, labelled `bug`, `limitation`, `enhancement`, `question`,
  `unchecked` (seen or suspected, not confirmed) and `strip`. The issue holds the details;
  `known-issues.md`, `strip-layout.md` and `docs/known-issues.md` link to it.
- **Before every release**, the whole of `testing-catalogue.md` runs on real windows, and the run is
  written to `test-runs/<version>.md`: every row passes, is skipped for want of its setup, or links
  the known issue it fails with. A tick that something once worked says nothing about the build
  being released, so the catalogue has no ticks, and the runs are kept instead. Then the tree and
  the commit messages since the last release are read for anything about a personal setup (no hook
  checks it).

## Diagnostics

- **`tyler debug at` and the real code share one decision.** Whether a press with the modifier
  grabs and whether focus follows the pointer are one pure function (`PointerCheck`) that returns
  the window or the reason for refusing it, so the diagnosis can't drift from what tylerd does.
  The client sends the point (the pointer's, from `CGEvent`, if none is given).
- **`tyler debug windows` only reports.** It reads every window afresh and shows where tylerd's
  picture differs; fixing drift on each sync waits until it shows what drifts and how often.
- **The log is the file tylerd already writes**, `~/.tyler/tyler.log`, by level (`log.level`,
  default `warning`): nothing grows in memory, `tail -f` watches it, and it starts empty at each
  start. Writes are plain and synchronous (a write to a regular file only copies into the page
  cache), and lines below the level aren't built (`@autoclosure`). The `debug` commands' output
  may change in any release.

## Considered and dropped

- **Focusing a workspace after its slide has started.** The focus call runs right after a slide
  starts and delays its first frame by 6–19 ms (the cost line's "first after"): latency, not
  stutter. Focusing later would send what is typed right after a switch to the window that just
  slid away.
- **Reading the focus from macOS before each command**, instead of trusting the focus
  notifications. It would cover any missed notification, but every command would then wait on
  the frontmost app (a hung app stalls each command until the Accessibility timeout), the focus
  would change along two paths that must agree (a read can lag tylerd's own focus call), and it
  would hide why a notification went missing. `tyler debug windows` reads the focus afresh and
  shows a missed one instead; revisit if it keeps finding them.
- **Pacing a resize from the start of each step** (as swipes are): with several neighbours, the
  writes of a step fill the interval, their echoes pile up, and the divider lags the pointer.
- **One clock for all motion.** In production the `Animator` and the pacing (`Throttle`,
  `Debounce`) run on the same continuous clock already; the tests give them separate fake clocks
  so they can drive a slide and a debounce independently, and merging them would rewrite that
  logic for nothing at run time.
- **Splitting `Interaction` into sessions and timing.** The enum already makes two motions at
  once impossible to write, and each case pairs a session with its own pacing on purpose (a
  swipe's throttle, a drag's pending frame); two parallel enums would have to be kept in step.
- **Moving every `extension WindowManager` into `Manager/`** so a SwiftLint rule could forbid
  them elsewhere: what remains in the feature folders is each feature's input handling and
  pacing, which belongs with its controller. SwiftLint checks the rules that matter instead: one
  writer to macOS, and controllers that never reach the manager.
- **`PointerInput` as three protocols** (the events, what to watch, the capture decision): each
  would have the same two implementations, the system's and the test fake. One protocol with a
  single `watch(_:)` and a `canCapture` property is narrow enough.
- **A vertical slide**: macOS clamps windows at the top and bottom of the screen.
- **A snapshot overlay for slides** (ScreenCaptureKit): needs Screen Recording permission. Still the
  only way to slide between side-by-side displays, and it would be smoother with many windows; see
  #25.
- **Private WindowServer API**: needs SIP off.
- **A `Scrollable` protocol** for swipes: it would have one implementation per case; an enum is
  enough (`SwipeTarget`). `ScrollingLayout` is a different thing: what a layout answers about its
  view.
- More in `REFACTORING.md` under "Considered and not worth it".
