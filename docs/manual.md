# tyler manual

tyler is a tiling window manager for macOS. It has two parts:

- **`tylerd`**, the server. It runs in the background, keeps track of your windows and moves them.
- **`tyler`**, the command-line client. Each call sends one command to `tylerd` and prints the reply.

tyler has no hotkeys of its own. To drive it from the keyboard, bind keys to `tyler` commands with a tool such as skhd, Karabiner-Elements or Raycast: see [Keybindings](keybindings.md).

This manual explains the concepts, running `tylerd`, the config file and every command. The other pages:

- [Layouts](layouts.md): `tall`, `grid`, `full` and the experimental `strip`
- [Features](features.md): swiping, the mouse, the menu bar, several displays, app assignments
- [Keybindings](keybindings.md): binding keys to `tyler` commands
- [Troubleshooting](troubleshooting.md): when windows go missing or nothing happens
- [Known issues](known-issues.md)

## Concepts

tyler arranges windows on displays. Each display holds a row of workspaces, each workspace holds an ordered list of windows, and a layout turns that list into window positions.

### Display

A physical screen: the built-in screen of a laptop or an external display. Displays are numbered: the main display (the one with the menu bar) is 1, the others follow from left to right, then from top to bottom. Each display has its own row of workspaces and tiles its own windows.

Commands act on the *focused display*: the display of the focused window, or the one a command last went to. See [Several displays](features.md#several-displays).

### Workspace

A set of windows with its own tiling list, layout and master ratio. A display has four workspaces by default (`workspaces.count` in the [config file](#configuration)), side by side in a row like pages. Workspace numbers are shared by all displays and run from left to right: with four each, the main display has 1 to 4 and a second display 5 to 8. Every tiled window belongs to exactly one workspace.

Exactly one workspace per display is on screen. Switching to another one (`tyler workspace focus`, a [swipe](features.md#swiping-between-workspaces), a click in the menu bar) slides its windows into view: going to the next workspace, the current windows leave to the left and the next ones come in from the right.

The windows of the workspaces that aren't on screen are *parked*: moved just past the edge of the display, at their own height, with only a one-point column visible. They are still open, and Cmd-Tab still lists them. Focusing a parked window, for example with Cmd-Tab, switches to its workspace.

### Window

tyler sorts every window into one of three kinds:

- **Tiled** windows belong to a workspace and are placed by its layout. Normal app windows are tiled.
- **Floated** windows are ones you took out of tiling with `tyler window float`. tyler leaves them where you put them.
- **Never-tiled** windows are dialogs, sheets, panels and other special windows. tyler leaves them alone.

Floated and never-tiled windows belong to no workspace, so they stay visible whichever workspace is on screen. Minimized windows and windows in native fullscreen leave the tiling list. When they come back, they are tiled on the current workspace.

New windows are tiled on the current workspace, right after the focused window (in `tall`, never in the master section: a window opened while a master has the focus goes to the top of the stack), unless the [config file](#configuration) assigns their app to another workspace ([`apps.<app>.workspace`](features.md#app-assignments)).

### Tiling list

Each workspace keeps its tiled windows in an ordered list. The first window is the *master*. A window's position in the list is its *slot* (1 is the master). Every window has a next and a previous window, and both wrap around at the ends of the list. `tyler window focus` moves the focus along the list and `tyler window swap` reorders it.

### Layout

A layout turns the tiling list into window frames, within the display's visible area (the screen without the menu bar and the Dock). Each workspace has its own layout (`tyler layout set`): `tall` (the master section on the left, the others stacked on the right), `grid` (columns two windows high), `full` (every window fills the area) or the experimental `strip` (a row of columns that scrolls). The *master section* of `tall` is the first windows of the list, stacked in the left column: the master alone, unless `tyler window promote` moves more windows there. The *master ratio* is the master column's share of the width in `tall` (`tyler layout ratio`). *Gaps* are the space between neighbouring windows and around them. See [Layouts](layouts.md).

## Running tylerd

```bash
tyler start    # start tylerd in the background
tyler status   # is it running, and which build?
tyler restart  # after rebuilding or installing a new version; windows stay put
tyler stop
```

`tyler start` runs the `tylerd` that sits in the same folder as `tyler` (after following symlinks), detached from the terminal: closing the terminal doesn't stop it. Its output goes to `~/.tyler/tyler.log`, which starts empty on every start. `tyler start` waits until `tylerd` answers, at most 10 seconds, and shows the end of the log if `tylerd` exits right away. It then checks that `tylerd` can reach your windows (see `access` under [status](#status)), waiting up to 4 seconds for apps that haven't answered yet, and fails with the reason and the fix if it can't. `tylerd` keeps running then.

You can also run `tylerd` yourself in a terminal, which keeps its output there; that's handy for debugging.

`tylerd` needs Accessibility permission. macOS grants it to the app that starts `tylerd`, so grant it in System Settings > Privacy & Security > Accessibility to the terminal you run `tyler start` (or `tylerd`) in. Without it, `tylerd` still runs and answers `tyler ping`, and the other commands print what to do. Once you grant the permission, `tylerd` picks it up within a second; you don't have to restart it. It also waits, and says so, while macOS refuses its Accessibility calls although the permission is on (a stale entry; see [Troubleshooting](troubleshooting.md#nothing-is-tiled-or-commands-say-there-is-no-permission)), and while the screen is locked, when macOS shows it no windows.

Run `tyler stop` before you switch off or remove that permission: taking it away while `tylerd` runs can stop all keyboard and mouse input until a forced restart (see [Troubleshooting](troubleshooting.md#nothing-is-tiled-or-commands-say-there-is-no-permission)). If the permission is switched off anyway, `tylerd` stops watching the mouse at once, leaves every window where it is and waits for the permission; once it is back, `tylerd` carries on with its workspaces.

As soon as it has permission, `tylerd` tiles the windows on the main display, ordered left to right as they were on screen.

**Stopping.** `tyler stop`, Ctrl-C in the terminal running `tylerd`, or SIGTERM (`pkill tylerd`) all stop it cleanly: `tylerd` puts every window it moved back where it was, parked windows included. A crash or `kill -9` skips this step, and windows of other workspaces stay parked at the edge of the display. Run `tyler start` to get them back: it tiles every window it finds, parked ones included, and a later `tyler stop` leaves them in view.

**Restarting** with `tyler restart` is different: the old `tylerd` leaves every window where it is and writes its workspaces (windows, order, focus, layouts, floated windows) to `~/.tyler/tyler.state.json`. The new `tylerd` carries on from that file and deletes it, so nothing moves and every window stays on its workspace. Windows closed in between are left out; windows opened in between join the current workspace, or their app's assigned workspace.

**After a rebuild** the running `tylerd` is still the old version, and a newer `tyler` may send it commands it doesn't know (`unknown request: tylerd is probably older than tyler`). `tyler status` warns when the `tylerd` binary has changed since it started. Run `tyler restart`.

Only one `tylerd` can run per socket. Starting a second one fails with `already running`.

## Configuration

`tylerd` reads its settings from `~/.config/tyler/tyler.toml` when it starts. Set `TYLER_CONFIG` to use another file. The file is optional: every setting has a default, so list only what you want to change. After editing it, run `tyler config reload` to apply it without restarting `tylerd`. To try a setting without editing the file, `tyler config set gaps.inner 8` changes it until `tylerd` stops or the file is reloaded, and `tyler config get gaps.inner` shows it; see [config set](#config-set).

[`tyler.toml`](tyler.toml) next to this manual is a sample with every setting at its default and a comment each: copy it to `~/.config/tyler/tyler.toml` as a starting point. The example below changes a few settings; the table after it lists them all.

```toml
# ~/.config/tyler/tyler.toml

[gaps]
inner = 8    # between neighbouring windows
outer = 12   # between the windows and the edge of the screen

[mouse]
follow-interval = 16   # milliseconds between steps of the layout following a drag
focus-follows = true   # the window the pointer rests on gets the focus
focus-delay = 100      # milliseconds the pointer rests before that
modifier = "option"    # drag anywhere in a window with this held to move it, right-drag to resize
gap-resize = true      # drag the gap between two windows to move the divider

[layouts]
cycle = ["tall", "full", "strip"]   # what `tyler layout next` goes through, in order
default = "full"                    # the layout new workspaces start with

[workspaces]
count = 6    # workspaces per display

[displays.1]
workspaces = [1, 2, 3, 4]   # the main display's workspaces

[displays.2]
workspaces = [5, 6, 7, 8]   # the second display's

[gestures]
fingers = 3            # fingers for swiping between workspaces
swipe-distance = 0.3   # trackpad widths to swipe a whole workspace across

[indicators.text]
enabled = false   # show only the map in the menu bar

[apps.Firefox]
workspace = 3        # new Firefox windows open on workspace 3
icon = "\uf269"      # a Nerd Font glyph instead of the app's icon on the map

[apps."com.mitchellh.ghostty"]   # an app can also be named by its bundle ID
workspace = 2
icon = "terminal"                # or an SF Symbol
```

| Setting | Meaning | Default |
| --- | --- | --- |
| `gaps.inner` | Space between neighbouring tiled windows | `0` |
| `gaps.outer` | Space between the tiled windows and the edge of the display's visible area | `0` |
| `mouse.follow-interval` | Least time between two steps of following the mouse (a window resized by its edge, a gap dragged, a window moved or resized with the modifier), in milliseconds (0 to 1000) | `16` |
| `mouse.focus-follows` | Whether the window the pointer rests on gets the focus (`true` or `false`, see [Focus follows mouse](features.md#focus-follows-mouse)) | `false` |
| `mouse.focus-delay` | How long the pointer rests on a window before it gets the focus, in milliseconds (0 to 1000) | `100` |
| `mouse.modifier` | The keys that, held while dragging anywhere in a window, move it (left button) or resize it (right): `"none"`, or names from `ctrl`, `option`, `cmd` and `shift` joined by `+` (see [Moving and resizing with the modifier](features.md#moving-and-resizing-with-the-modifier)) | `"option"` |
| `mouse.gap-resize` | Whether dragging the gap between two tiled windows moves the divider between them (`true` or `false`, see [Resizing with the mouse](features.md#resizing-with-the-mouse)); needs `gaps.inner` | `true` |
| `layouts.cycle` | The layouts `tyler layout next` and the menu go through, in order: a list of `"tall"`, `"grid"`, `"full"` and `"strip"`, each at most once. Any layout can still be set by name | `["tall", "grid", "full"]` |
| `layouts.default` | The layout every workspace starts with: `"tall"`, `"grid"`, `"full"` or `"strip"`. Workspaces that already exist keep theirs on `tyler config reload` and `tyler restart`; only new ones (from a larger `workspaces.count`, a new display) start with the new default. `tyler stop` and `tyler start` apply it everywhere | `"tall"` |
| `workspaces.count` | How many workspaces each display has (1 to 10) | `4` |
| `displays.<n>.workspaces` | The numbers of display `<n>`'s workspaces (1 to 99, at most 10 per display) | `count` each, numbered on from the previous display |
| `gestures.swipe` | Whether a sideways trackpad swipe moves between workspaces (`true` or `false`) | `true` |
| `gestures.fingers` | How many fingers that swipe takes (3 or 4) | `3` |
| `gestures.swipe-distance` | How far your fingers travel to swipe a whole workspace across, in trackpad widths (0.1 to 1.0): lower is more sensitive | `0.3` |
| `animations.swap` | How long [`tyler window swap`](#window-swap) takes to move the windows to their new places, in milliseconds (0 to 1000); 0 moves them at once | `250` |
| `animations.drag-preview` | How long the preview of a [drag](features.md#moving-windows-by-dragging) takes to move a window to where a drop would put it, in milliseconds (0 to 1000); 0 moves it at once | `200` |
| `animations.retile` | How long the windows that stay on a workspace take to slide into their new slots when one leaves it (closed, minimized, floated, its app quit), in milliseconds (0 to 1000); 0 moves them at once. In the `strip` layout they always move at once | `250` |
| `indicators.text.enabled` | Whether the menu bar shows the workspace numbers (`1 [2] 3 4  ▥`) | `true` |
| `indicators.map.enabled` | Whether the menu bar shows the map of the workspaces | `true` |
| `indicators.map.show-icons` | Whether the map shows each window's app icon | `true` |
| `indicators.map.icon-font` | The font of glyph icons set by `apps.<app>.icon` (family or PostScript name) | `"Symbols Nerd Font"` |
| `editor.command` | What the menu's Open config and [`tyler config edit`](#config-edit) outside a terminal run, with the config file's path appended: a shell command such as `"open -na Ghostty --args -e nvim"` (run by `/bin/sh`, so give a full path if a program isn't found). Empty runs `$VISUAL` or `$EDITOR` in Terminal, read from your login shell if `tylerd` doesn't have them, and the default text editor if neither is set | `""` |
| `log.level` | What `tylerd` writes to `~/.tyler/tyler.log`: `"error"`, `"warning"` (what you should know, such as an app it gave up on), `"info"` (each decision: a focus, a press with the modifier passed on to the app, a dropped notification) or `"debug"` (every step, such as each rest of the pointer). See [Troubleshooting](troubleshooting.md#where-to-look) | `"warning"` |
| `apps.<app>.workspace` | The number of the workspace that new windows of `<app>` open on | none |
| `apps.<app>.icon` | An SF Symbol's name, or one glyph, that the map shows on `<app>`'s windows instead of its icon | none |

Gaps are whole numbers in points, the unit macOS uses for window positions (on a Retina display, one point is two pixels).

Workspace numbers are shared by all displays: each number belongs to one display. Each `[displays.<n>]` table holds the settings of one display, by display number (1 is the main display, the one with the menu bar). Without a list of `workspaces`, a display gets `workspaces.count` workspaces, numbered on from the previous display: with the default of 4, the main display has 1 to 4 and a second display 5 to 8. With one, it gets those, and a display without one gets `workspaces.count` workspaces numbered after the highest listed one. A display's workspaces are always in number order. Workspaces of a display that isn't connected wait on the main display's row, and go back when it is.

Changing `workspaces.count` or a display's `workspaces` and running `tyler config reload` takes effect at once. New workspaces are added in number order. When you remove workspaces, their windows move to the last workspace of their display, after the windows already there; if the workspace on screen was removed, the new last one comes into view.

Each `[apps.<app>]` table holds the settings of one app; it lists only what it sets. Name the app as the `APP` column of `tyler window list` shows it, or by its bundle ID (`osascript -e 'id of app "Firefox"'` prints it); both ignore case. Quote names with spaces or dots: `[apps."Google Chrome"]`, `[apps."org.mozilla.firefox"]`. Where an app has a table by bundle ID and one by name, a setting in the bundle ID's table wins.

`workspace` sends the app's new windows to a workspace: one of the shared numbers above (1 to 99); if any display lists its `workspaces`, it must be one of those. An assignment applies once, when a window is tiled for the first time; see [App assignments](features.md#app-assignments). Changing it and running `tyler config reload` affects windows opened afterwards, not the ones already open.

`icon` gives the app an SF Symbol or a Nerd Font glyph on the map instead of its icon; see [Menu bar items](features.md#menu-bar-items) for how to write them.

`mouse.follow-interval` trades smoothness for keeping up with slow apps; see [Resizing with the mouse](features.md#resizing-with-the-mouse).

The file is [TOML](https://toml.io). tyler reads the parts of TOML its settings need: tables, keys, numbers, strings, booleans and comments. Unknown settings are errors, so a typo doesn't go unnoticed. If the file has an error when `tylerd` starts, it prints the error and starts with the defaults; fix the file and run `tyler config reload`.

## Command reference

```
tyler <command> [arguments]
tyler <window|workspace|layout|display|config|debug> <command> [arguments]
tyler --version
```

Commands are grouped by what they act on: `tyler window focus next` focuses a window, `tyler workspace focus next` a workspace, `tyler config set` a setting. The commands about `tylerd` itself, and `tiling`, stand alone. `tyler window` (or `workspace`, `layout`, `display`, `config`, `debug`) on its own lists the commands it has. The `debug` commands are for finding problems, and their output may change in any release.

`tyler --version` prints the version of `tyler`, such as `tyler 0.1.0`; `tyler status` also shows the version of the running `tylerd`.

| Command | What it does |
| --- | --- |
| `start` | Start `tylerd` in the background |
| `stop` | Stop `tylerd`; windows go back where they were |
| `restart` | Stop `tylerd` and start it again, keeping the windows in place |
| `status` | Show whether `tylerd` is running, and which build |
| `ping` | Check that `tylerd` is running |
| `tiling on\|off\|toggle` | Start or stop tiling |
| `window list [--json]` | Show the windows `tylerd` is tracking |
| `window focus next\|prev\|master` | Move focus within the tiling list |
| `window swap next\|prev\|master` | Swap the focused window with another one |
| `window promote` | Move the focused window into the master section of `tall` |
| `window demote` | Move the focused window out of the master section of `tall` |
| `window float on\|off\|toggle` | Float the focused window, or tile it again |
| `window close` | Close the focused window |
| `window size half\|full\|quarter\|next` | Size the focused window in the strip layout |
| `window move-to-workspace prev\|next\|<n> [--follow]` | Send the focused window to another workspace |
| `window move-to-display prev\|next\|<n> [--follow]` | Send the focused window to another display |
| `workspace focus prev\|next\|<n>` | Switch to another workspace |
| `workspace move-to-display prev\|next\|<n>` | Move the current workspace to another display |
| `workspace retile` | Put every tiled window back into its slot |
| `layout set tall\|grid\|full\|strip` | Choose the layout |
| `layout next` | Switch to the next layout of `layouts.cycle` |
| `layout ratio +<step>\|-<step>` | Widen or narrow the master column |
| `display focus prev\|next\|<n>` | Focus another display |
| `config get [<setting>]` | Show a setting, or every setting |
| `config set <setting> <value>` | Change a setting until `tylerd` stops or the config is reloaded |
| `config reload` | Read the config file again and apply it |
| `config edit` | Open the config file in your editor |
| `debug at [<x> <y>] [--json]` | Show what `tylerd` sees and does at a point on screen |
| `debug windows [--json]` | Show where `tylerd`'s picture of the windows differs from what macOS reports |

Commands that change windows act on the current workspace. All of them except `start`, `stop`, `restart`, `status`, `ping`, `tiling`, `window list`, `window close` and the `config` commands need tiling to be on; with tiling off they print ``tiling is off (use `tyler tiling on`)``.

### start, stop, restart

```bash
tyler start
tyler stop
tyler restart
```

`start` starts `tylerd` in the background (see [Running tylerd](#running-tylerd)) and prints its pid. If `tylerd` is already running, it says so and does nothing. Either way it checks that `tylerd` can reach the windows: if `access` (see [status](#status)) needs fixing, `start` prints the fix and exits with status 1, leaving `tylerd` running; a locked screen gets a note. `restart` checks the new `tylerd` the same way.

`stop` asks `tylerd` to quit, which puts every window back where it was, and waits until it has. It is not an error if `tylerd` isn't running.

`restart` stops `tylerd` and starts it again, keeping every window where it is and on its workspace (see [Running tylerd](#running-tylerd)): use it after `make build` or `make install`. A `tylerd` from before restarts kept windows can't hand them over; it is stopped normally, its windows go back where they were, and `restart` says so.

A `tylerd` started before these commands existed can't be stopped this way; `tyler` says so. Stop it once with `pkill tylerd` (or Ctrl-C), then use `tyler start`.

### status

```bash
tyler status
```

```
tylerd is running (pid 4711, up 2h 5m)
  version 0.1.0
  binary  /Users/you/.local/bin/tylerd
  config  /Users/you/.config/tyler/tyler.toml
  tiling  on
  access  sees the windows
```

`tiling` is `on`, `off` or `waiting for Accessibility permission`. `access` says whether `tylerd` can reach the windows:

| `access` | Meaning |
| --- | --- |
| `sees the windows` | All is well. |
| `no Accessibility permission` | Grant it; `tylerd` starts by itself once it's there. |
| `Accessibility calls refused although the permission is on` | The permission's entry is probably stale; a warning says how to fix it. |
| `sees none of the windows on screen` | `tylerd` tracks windows but none of those on screen: the same fix. |
| `waiting for the screen to be unlocked` | macOS shows no windows while the screen is locked; `tylerd` starts once it is unlocked. |
| `some apps haven't answered yet` | Right after a start; `tylerd` is still trying them. |
 If the `tylerd` binary has changed since it started, or `tylerd` is another version than `tyler`, a warning suggests `tyler restart`. Exits with status 1 if `tylerd` isn't running.

### ping

```bash
tyler ping
```

Prints `pong` if `tylerd` is running.

### tiling

```bash
tyler tiling on
tyler tiling off
tyler tiling toggle
```

`tiling off` stops `tylerd` from moving windows. Windows on the current workspace stay where they are, and windows parked on other workspaces come back to where they were before `tylerd` moved them. Use it when something goes wrong, or before arranging windows by hand.

`tiling on` tiles every eligible window onto the current workspace, keeping the order the list had before. Windows opened while tiling was off go to their app's assigned workspace, if it has one.

### window list

```bash
tyler window list
tyler window list --json
```

Shows every window `tylerd` knows about, one per row:

| Column | Meaning |
| --- | --- |
| `ID` | The system's window number |
| `WORKSPACE` | The workspace (from 1) the window is tiled on, or `-` |
| `SLOT` | The position in that workspace's tiling list (1 is the master), or `-` |
| `APP` | The application |
| `TITLE` | The window title |
| `FRAME` | Position and size, as `x,y widthxheight` in points from the top-left of the main display |
| `DISPLAY` | The physical display the window is on |
| `FLAGS` | Any of `focused`, `min` (minimized), `full` (native fullscreen), `floated` (floated with `window float`), `dialog`, `float` (a floating panel), `other` (a window that is never tiled) |

`--json` prints the same information as a JSON array, for scripts.

### window focus

```bash
tyler window focus next    # the next window in the list (wraps to the first)
tyler window focus prev    # the previous window (wraps to the last)
tyler window focus master  # the first window
```

Focuses a tiled window on the current workspace and brings its app to the front.

### window swap

```bash
tyler window swap next
tyler window swap prev
tyler window swap master
```

Swaps the focused window with its neighbour in the list (wrapping around) or with the master, then re-tiles. The two windows slide into each other's slots, changing size on the way, taking `animations.swap` milliseconds (0 swaps them at once). The focused window moves and keeps the focus. If the focused window already is the master, `window swap master` swaps it with the second window.

### window promote, window demote

```bash
tyler window promote
tyler window demote
```

Move the focused window between the master section and the stack of the `tall` layout. `window promote` moves a window from the stack to the bottom of the master section, which then holds one more window, stacked in the left column; promoting the last window of the stack leaves one column. `window demote` moves a window from the master section to the top of the stack. Demoting the only master gives its place to the window after it. The windows slide to their new slots as in [`window swap`](#window-swap), taking `animations.swap` milliseconds. A window that already is in that section stays where it is and `tyler` says so; in another layout `tyler` says that only `tall` has a master section. Each workspace keeps its own master section; when a master closes, the section shrinks with it.

### window float

```bash
tyler window float on      # float the focused window
tyler window float off     # tile it again
tyler window float toggle  # float it if it is tiled, tile it if it floats
```

`on` takes the focused window out of the tiling list and leaves it where it is; `off` puts a floated window back into the list. If the window already is in that state, nothing changes and `tyler` says so (`already floating`, `already tiled`). Windows that are never tiled (dialogs, panels) can't be floated.

### window close

```bash
tyler window close
```

Closes the focused window, as its close button does: the app keeps running, and an app with unsaved changes may first ask whether to save them. The rest of the workspace re-tiles once the window is gone, the windows sliding into their new slots over `animations.retile` milliseconds, and macOS decides which window gets the focus next. It closes any focused window, tiled, floated or never tiled, and works with tiling off. A window without a close button (some panels) can't be closed this way.

### window size

```bash
tyler window size half     # half the width, the full height (the default)
tyler window size full     # the whole width and height
tyler window size quarter  # stack it with the next window: half the width, half the height each
tyler window size next     # cycle: half, full, quarter, half, ...
```

Sets the focused window's size in the `strip` layout and prints it. Like the strip layout, this command is experimental and may change. `quarter` stacks two windows in one column: the focused window on top and the next window below it. If the next window already shares a column (or there is none), the previous window goes on top instead. Setting either window of a stacked pair to `half` or `full` puts the other back to `half`, and so does closing, floating or moving one of them away.

Other layouts ignore the size but keep it for when the workspace switches to `strip`. A window forgets its size when it leaves tiling (floated, minimized, closed), and keeps it when it moves to another workspace (a `quarter` arrives as `half`).

### window move-to-workspace

```bash
tyler window move-to-workspace next
tyler window move-to-workspace 2
tyler window move-to-workspace prev --follow
```

Sends the focused window to another workspace, where it becomes the focused window. Without `--follow` the window slides away towards its new workspace (to the right for `next`, to the left for `prev`), the remaining windows re-tile, and you stay on the current workspace. With `--follow` you switch to the target workspace along with the window. Sending away the last window of the current workspace leaves no window focused, as on any empty workspace.

Only tiled windows can be moved.

### window move-to-display

```bash
tyler window move-to-display 2
tyler window move-to-display next --follow
```

Sends the focused window to the workspace on screen on another display. It goes in after the window focused there, takes its slot at once and becomes that workspace's focused window; the windows it leaves re-tile. Without `--follow` the focus stays on the window's old display (on the window that last had focus there, or none if the workspace is now empty); with `--follow` the focus goes along with the window. `next` and `prev` count from the window's display and wrap. To send a window to a workspace that isn't on screen, use `window move-to-workspace` with its number.

Only tiled windows can be moved.

### workspace focus

```bash
tyler workspace focus next  # the next workspace (after the last comes the first)
tyler workspace focus prev  # the previous workspace (before the first comes the last)
tyler workspace focus 3     # workspace 3 (workspaces are numbered from 1)
```

Switches to another workspace. The current windows slide out and are parked, the target workspace's windows slide in, and focus goes to the window that last had focus there. On an empty workspace no window has focus (tylerd itself becomes the active app), so what you type doesn't reach a parked window. A floated window stays on screen and keeps the focus.

Focusing a parked window yourself, for example with Cmd-Tab, also switches to its workspace.

### workspace move-to-display

```bash
tyler workspace move-to-display 2
tyler workspace move-to-display next
```

Moves the focused display's current workspace, with its windows, layout and number, to another display. There it joins the row in number order, comes on screen and gets the focus; the workspace that was on screen there is parked. The display it left shows its next workspace (or the previous one if it was the last). Nothing slides: the windows jump.

The workspace belongs to its new display from then on: if that display is unplugged, the workspace waits on display 1, and it goes back when the display returns, also after `tyler restart`. `tyler config reload` keeps it there too. A display's only workspace can't be moved away.


### workspace retile

```bash
tyler workspace retile
```

Puts every tiled window on the current workspace back into its slot, for example after an app moved or resized one of its windows itself. Windows you drag with the mouse snap back on their own (see [Resizing with the mouse](features.md#resizing-with-the-mouse)).

### layout set, layout next

```bash
tyler layout set tall
tyler layout set grid
tyler layout set full
tyler layout set strip  # experimental
tyler layout next       # the next layout of layouts.cycle: tall, grid, full, tall, ...
```

Sets the layout of the current workspace and prints its name. `strip` is experimental (see [Layouts](layouts.md#strip--experimental)), so `layout next` leaves it out unless `layouts.cycle` in the [configuration](#configuration) lists it. From a layout the cycle doesn't list, `layout next` goes to the cycle's first.

### layout ratio

```bash
tyler layout ratio +0.05  # widen the master column
tyler layout ratio -0.05  # narrow it
```

Changes the master column's share of the width in the `tall` layout. The sign is required. The `grid` has no master ratio: on a grid workspace `tyler` says so and nothing moves. The ratio starts at 0.5 and stays between 0.1 and 0.9; at a limit, `tyler` says so and nothing moves.

### display focus

```bash
tyler display focus 2     # display 2 (the main display is 1; see Display)
tyler display focus next  # the next display (after the last comes the first)
tyler display focus prev  # the previous display (before the first comes the last)
```

Makes another display the focused one, so the commands that follow act on it, and focuses the window that last had focus on its current workspace. Nothing moves, not even the pointer. If that workspace is empty, no window has focus, as after `tyler workspace focus` to an empty workspace. With one display, `next` and `prev` stay on it.

### config get

```bash
tyler config get gaps.inner                           # 8
tyler config get gaps                                 # the [gaps] table
tyler config get 'apps."com.mitchellh.ghostty".icon'  # quote names with dots
tyler config get                                      # every setting
```

Prints the setting `tylerd` uses now, named as in the [config file](#configuration): the file's value, the default, or what `config set` changed. A table of settings prints as the file would write it, and no name prints every setting, defaults included, as a file `tylerd` would read the same way. App names ignore case. A setting that isn't set (an app's `icon`, a display's `workspaces`) is an error, as is a name that isn't a setting.

### config set

```bash
tyler config set gaps.inner 8
tyler config set layouts.default strip            # a word needs no quotes
tyler config set layouts.cycle '["tall", "strip"]'
tyler config set apps.Slack.workspace 3
```

Changes one setting until `tylerd` stops or `tyler config reload` reads the file again, to try a setting without editing the file; `tyler restart` drops it too. It takes effect as if the file said so, and is checked as the file is: a value that can't be used is an error and changes nothing. Values are written as in the file (`8`, `true`, `"tall"`, `[1, 2]`); a word without quotes is a string. `tyler status` lists the settings `config set` changed.

### config reload

```bash
tyler config reload
```

Reads the config file again and applies it, dropping what `config set` changed. Windows on the current workspace move to their new frames at once; the other workspaces use the new settings when you switch to them. With tiling off, nothing moves until you turn it back on.

Prints `reloaded <path>`. If the file has an error, `tyler config reload` prints it with its line number, exits with status 1, and the current settings stay, `config set` changes included. If there is no file, the defaults apply.

### config edit

```bash
tyler config edit
```

Opens the config file in an editor, creating an empty one if there is none. In a terminal with `$VISUAL` or `$EDITOR` set, it runs that editor right there and waits for it; when you quit the editor, it runs `tyler config reload` and prints what that prints. If `tylerd` isn't running, it edits the file `tylerd` would read (`TYLER_CONFIG` or `~/.config/tyler/tyler.toml`) and doesn't reload.

Run from a hotkey, without a terminal, or with neither variable set, it asks `tylerd` to open the file as the menu's Open config does: with [`editor.command`](#configuration) if you set it, else in `$VISUAL` or `$EDITOR` in Terminal, else in your default text editor. It prints `opened <path>`, and needs `tylerd` running. Run `tyler config reload` after saving.

### debug at

```bash
tyler debug at            # where the pointer is
tyler debug at 300 400    # a point in screen coordinates: from the top left of the main display
tyler debug at --json
```

Shows what `tylerd` sees at a point on screen and what it would do there, for finding out why [focus follows mouse](features.md#focus-follows-mouse) or [dragging with the modifier](features.md#moving-and-resizing-with-the-modifier) does nothing: the display the point is on and its visible frame, the window on top there with its workspace (as `tylerd` sees it: windows that clicks go through, such as the Dock's, which covers its whole display, or the cursor while the screen is shared, are left out; a window `tylerd` doesn't track is named by the app or process that owns it), whether a menu is open, whether a slide, swipe or drag is under way, and whether tiling is on. The last two lines say whether a press with the modifier would grab the window and whether focus would follow the mouse to it, each with the reason when not:

```
point        300,300, on display 1, visible frame 55,39 1745x1130
on top       window 10705 (Ghostty "~"), layer 0, workspace 1
menu open    no
interaction  idle
tiling       on
modifier     option
grab         yes, window 10705
focus        no: the window on top has the focus already
```

To check a point the pointer has to be at, such as over a window, run it after a pause and move the pointer there meanwhile: `sleep 3; tyler debug at`. Like every `debug` command, its output may change in any release.

### debug windows

```bash
tyler debug windows
tyler debug windows --json
```

Reads every window `tylerd` tracks again and shows where that differs from what `tylerd` believes: whether a window is minimized or fullscreen, its frame, its title and its kind. `tylerd` reads a window again only when its app reports a change, so a change it missed (a window that stays in the layout after being minimized, for example) shows here:

```
13595  Ghostty  minimized  tylerd: no  macOS: yes
windows tylerd doesn't track:
  14001 Finder "Copy", dialog
apps tylerd can't observe: Busy
```

Two lines are about the focus, both naming the window macOS focuses now in the first column and under `macOS:`. A `focus` line means `tylerd` has another window (or none) as focused: it missed macOS reporting the change, so commands such as `window close` act on that other window. A `workspace-focus` line means the window's workspace has another window as focused, the one `window focus` and `window swap` act on. Right after a `tyler` command moves the focus, either can show for a moment, until macOS reports the new focus. If macOS reports no focused window, the focus isn't compared.

After the differences come the windows of the apps `tylerd` observes that it doesn't track, and the apps it couldn't observe at all, whose windows it therefore leaves alone. Some apps refuse while none of their windows is on screen; `tylerd` tries again when such an app comes to the front. When everything matches it prints `no differences in <n> windows`. It moves nothing and changes nothing; `tyler restart` reads every window again.

## Exit status and errors

| Exit status | Meaning |
| --- | --- |
| 0 | The command succeeded. Any message is printed to standard output. |
| 1 | `tylerd` refused or failed (for example `no tiled windows`), isn't running, or has no Accessibility permission; for `start` and `restart`, also when `tylerd` can't reach the windows. The reason is printed to standard error. |
| 2 | The command line is wrong. `tyler` prints what's wrong, followed by the usage summary. |

If some windows couldn't be moved (an app refused, or a window closed meanwhile), or the window that should get the focus refused it, the command still succeeds and prints what it did followed by what went wrong, for example `workspace focus 2; 1 window could not be placed` or `workspace focus 2; cannot focus window 4242: …`.

`tiling on` and `tiling off` also succeed before Accessibility permission is granted: tylerd remembers the choice and applies it once it starts, and the reply says so.

## Environment

| Variable | Meaning |
| --- | --- |
| `TYLER_CONFIG` | Path of the config file. Default: `~/.config/tyler/tyler.toml`. |
| `TYLER_SOCKET` | Path of the socket `tyler` and `tylerd` talk over. Default: `~/.tyler/tyler.sock`. Set the same value for both to run a separate instance. `tyler start` writes the log next to it, with `.log` instead of `.sock`. |
