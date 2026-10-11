# tyler manual

tyler is a tiling window manager for macOS. It has two parts:

- **`tylerd`**, the server. It runs in the background, keeps track of your windows and moves them.
- **`tyler`**, the command-line client. Each call sends one command to `tylerd` and prints the reply.

tyler has no hotkeys of its own. To drive it from the keyboard, bind keys to `tyler` commands with a tool such as skhd, Karabiner-Elements or Raycast.

## Concepts

tyler arranges windows on displays. Each display holds a row of workspaces, each workspace holds an ordered list of windows, and a layout turns that list into window positions.

### Display

A physical screen: the built-in screen of a laptop or an external monitor. tyler calls these *displays*. For now tyler manages only the main display (the one with the menu bar). Windows on other displays are left alone.

### Workspace

A set of windows with its own tiling list, layout and master ratio. A display has four workspaces by default (`workspaces.count` in the [config file](#configuration)), side by side in a row like pages and numbered from 1 on the left. Exactly one workspace per display is on screen; switching to another one slides its windows into view (`tyler workspace`): going to the next workspace, the current windows leave to the left and the next ones come in from the right. Every tiled window belongs to exactly one workspace.

The windows of the workspaces that aren't on screen are *parked*: moved just past the right edge of the display, at their own height, with only a one-point column visible. They are still open, and Cmd-Tab still lists them. Focusing a parked window, for example with Cmd-Tab, switches to its workspace.

### Swiping between workspaces

Swipe sideways with three fingers on the trackpad to move between workspaces. The windows follow your fingers. Swipe left to bring in the next workspace from the right, and swipe right to bring in the previous one; from the first workspace, a swipe right wraps around to the last. When you lift your fingers, the next workspace comes into view if you swiped more than halfway, or with a quick flick even before that; otherwise the windows slide back. Changing your mind halfway works too: swipe back past where you started and the other neighbour comes in instead. The workspace that comes into view gets the focus, as with `tyler workspace`.

A swipe does nothing while tiling is off, while you drag a window, or when there is only one workspace. Vertical swipes and swipes with another number of fingers are left to macOS. Any command in the middle of a swipe puts the windows back first.

macOS has its own sideways swipes, and tylerd doesn't stop them: in System Settings > Trackpad > More Gestures, set *Swipe between full-screen applications* to four fingers (or off), and make sure *Swipe between pages* doesn't use three fingers. Otherwise a swipe may switch Spaces or go back a page as well. To use four fingers for tyler instead, set `gestures.fingers = 4` and give macOS's swipe three fingers or turn it off. `gestures.swipe = false` turns swiping off.

### Window

tyler sorts every window into one of three kinds:

- **Tiled** windows belong to a workspace and are placed by its layout. Normal app windows are tiled.
- **Floated** windows are ones you took out of tiling with `tyler float toggle`. tyler leaves them where you put them.
- **Never-tiled** windows are dialogs, sheets, panels and other special windows. tyler leaves them alone.

Floated and never-tiled windows belong to no workspace, so they stay visible whichever workspace is on screen. Minimized windows and windows in native fullscreen leave the tiling list. When they come back, they are tiled on the current workspace.

New windows are tiled on the current workspace, right after the focused window, unless the [config file](#configuration) assigns their app to another workspace (`[assign]`).

### Tiling list

Each workspace keeps its tiled windows in an ordered list. The first window is the *master*. A window's position in the list is its *slot* (1 is the master). Every window has a next and a previous window, and both wrap around at the ends of the list. `tyler focus` moves the focus along the list and `tyler swap` reorders it.

### Layout

A layout turns the tiling list into window frames, within the display's visible area (without the menu bar and the Dock):

- `tall`: the master fills the left column, and the other windows are stacked in the right column. Two windows sit side by side; three give one on the left and two on the right.
- `full`: every window fills the whole area.
- `strip`: the windows form one long row of columns that scrolls left and right, and the display shows as many whole columns as fit. Each window is half the width by default, so two windows look like `tall`. Focusing a window out of view scrolls to it. Windows out of view wait at the right edge, like the windows of other workspaces.

The *master ratio* is the master column's share of the width in `tall`. Each workspace has its own layout and master ratio (`tyler layout`, `tyler ratio`).

### Resizing with the mouse

In `tall`, drag the edge between two tiled windows and the layout follows while you drag (in steps at most `mouse.follow-interval` apart, see Configuration):

- the edge between the master and the stack sets the master ratio (the same one `tyler ratio` changes)
- the edge between two stacked windows sets their heights; the other stacked windows keep theirs

When you let go of the mouse button, every window snaps into its slot. Edges that aren't between two windows (the outer edges, the master's top and bottom) snap back, and so does a window you moved by its title bar without dropping it on another one (see below). A divider stops before either neighbour drops below a tenth of their shared space. Stack heights belong to the slot, not the window: a window that moves into a slot takes its height. Each workspace keeps its own heights, and `tyler restart` keeps them. `full` doesn't follow the mouse; windows snap back.

### Swapping windows by dragging

Drag a tiled window by its title bar over another tiled window, and that window moves into the slot of the one you're dragging, to show what will happen. Let go there, and the two windows swap slots: the dragged window takes the other's place in the tiling list, and each takes the size of its new slot. Move on to a third window and the first goes back; move back over the dragged window's own slot, onto a gap or outside the tiled area, and nothing will swap.

What counts is the window under the mouse pointer, not the one the dragged window covers most. Letting go anywhere without a window under the pointer puts the dragged window back in its slot. The window you drag keeps focus. In `full` every window fills the same area, so dragging never swaps there. Floated windows take no part: you can't drag one into the layout, and a tiled window can't swap with one. A command or a workspace switch in the middle of a drag ends it, and the windows go back to their slots.

*Gaps* are the space between neighbouring windows (inner) and between the windows and the edge of the area (outer). They are the same on every workspace and come from the config file.

### Menu bar item

While `tylerd` runs, it shows the workspaces in the menu bar, for example `1 [2] 3 4  ▥`:

- the number of each workspace, from left to right: the one on screen is in brackets (`[2]`), and empty ones are faint
- the symbol of the current workspace's layout: `▥` for tall, `▢` for full (in full, the other windows are stacked behind the one you see)

Without tiling it says `tyler: tiling off`, and before Accessibility permission is granted `tyler: no access`. Clicking it opens a menu to switch workspaces, cycle the layout and turn tiling on or off; these do the same as the `tyler` commands. On a MacBook with a notch, macOS hides menu bar items that don't fit next to it.

## Running tylerd

```bash
tyler start      # start tylerd in the background
tyler status     # is it running, and which build?
tyler restart    # after rebuilding or installing a new version; windows stay put
tyler stop
```

`tyler start` runs the `tylerd` that sits in the same folder as `tyler` (after following symlinks), detached from the terminal: closing the terminal doesn't stop it. Its output goes to `~/.tyler/tyler.log`, which starts empty on every start. `tyler start` waits until `tylerd` answers, at most 10 seconds, and shows the end of the log if `tylerd` exits right away.

You can also run `tylerd` yourself in a terminal, which keeps its output there; that's handy for debugging.

`tylerd` needs Accessibility permission. macOS grants it to the app that starts `tylerd`, so grant it in System Settings > Privacy & Security > Accessibility to the terminal you run `tyler start` (or `tylerd`) in. Without it, `tylerd` still runs and answers `tyler ping`, and the other commands print what to do. Once you grant the permission, `tylerd` picks it up within a second; you don't have to restart it.

As soon as it has permission, `tylerd` tiles the windows on the main display, ordered left to right as they were on screen.

**Stopping.** `tyler stop`, Ctrl-C in the terminal running `tylerd`, or SIGTERM (`pkill tylerd`) all stop it cleanly: `tylerd` puts every window it moved back where it was, parked windows included. A crash or `kill -9` skips this step, and windows of other workspaces stay parked at the right edge of the display.

**Restarting** with `tyler restart` is different: the old `tylerd` leaves every window where it is and writes its workspaces (windows, order, focus, layouts, floated windows) to `~/.tyler/tyler.state.json`. The new `tylerd` carries on from that file and deletes it, so nothing moves and every window stays on its workspace. Windows closed in between are left out; windows opened in between join the current workspace, or their app's assigned workspace.

**After a rebuild** the running `tylerd` is still the old version, and a newer `tyler` may send it commands it doesn't know (`unknown request: tylerd is probably older than tyler`). `tyler status` warns when the `tylerd` binary has changed since it started. Run `tyler restart`.

Only one `tylerd` can run per socket. Starting a second one fails with `already running`.

## Configuration

`tylerd` reads its settings from `~/.config/tyler/tyler.toml` when it starts. Set `TYLER_CONFIG` to use another file. The file is optional: every setting has a default, so list only what you want to change. After editing it, run `tyler reload` to apply it without restarting `tylerd`.

```toml
# ~/.config/tyler/tyler.toml

[gaps]
inner = 8    # between neighbouring windows
outer = 12   # between the windows and the edge of the screen

[mouse]
follow-interval = 50   # milliseconds between steps of the layout following a drag

[workspaces]
count = 6    # workspaces per display

[gestures]
fingers = 3            # fingers for swiping between workspaces
swipe-distance = 0.3   # trackpad widths to swipe a whole workspace across

[assign]
Firefox = 3                  # new Firefox windows open on workspace 3
"com.mitchellh.ghostty" = 2  # an app can also be named by its bundle ID
```

| Setting | Meaning | Default |
| --- | --- | --- |
| `gaps.inner` | Space between neighbouring tiled windows | `0` |
| `gaps.outer` | Space between the tiled windows and the edge of the display's visible area | `0` |
| `mouse.follow-interval` | Least time between two steps of the layout following a window you resize with the mouse, in milliseconds (0 to 1000) | `50` |
| `workspaces.count` | How many workspaces each display has (1 to 10) | `4` |
| `gestures.swipe` | Whether a sideways trackpad swipe moves between workspaces (`true` or `false`) | `true` |
| `gestures.fingers` | How many fingers that swipe takes (3 or 4) | `3` |
| `gestures.swipe-distance` | How far your fingers travel to swipe a whole workspace across, in trackpad widths (0.1 to 1.0): lower is more sensitive | `0.3` |
| `assign.<app>` | The workspace that new windows of `<app>` open on | none |

Gaps are whole numbers in points, the unit macOS uses for window positions (on a Retina display, one point is two pixels).

Changing `workspaces.count` and running `tyler reload` takes effect at once. New workspaces are added at the end of the row. When you remove workspaces, their windows move to the new last workspace, after the windows already there; if the workspace on screen was removed, the new last one comes into view.

In `[assign]`, each line sends an app's new windows to a workspace. Name the app as the `APP` column of `tyler list` shows it, or by its bundle ID (`osascript -e 'id of app "Firefox"'` prints it); both ignore case. Quote names with spaces or dots: `"Google Chrome" = 2`. The workspace number must be within `workspaces.count`.

An assignment applies once, when a window is tiled for the first time: when it opens, or when `tylerd` starts and finds it open. If the workspace isn't on screen, the window is parked there. Apps usually focus a window they open, and focusing a parked window switches to its workspace, so you follow the window there; a window that opens in the background just waits on its workspace. After that, the window behaves like any other: `move-to-workspace` moves it, and it stays where you put it when you float it, minimize it or take it out of fullscreen. Changing `[assign]` and running `tyler reload` affects windows opened afterwards, not the ones already open.

Each step of following a drag moves every other window, and slow apps take a while to move. A shorter `mouse.follow-interval` looks smoother but can fall behind the mouse with slow apps; a longer one keeps up but moves in coarser steps. `0` follows every resize the app reports.

The file is [TOML](https://toml.io). tyler reads the parts of TOML its settings need: tables, keys, numbers, strings, booleans and comments. Unknown settings are errors, so a typo doesn't go unnoticed. If the file has an error when `tylerd` starts, it prints the error and starts with the defaults; fix the file and run `tyler reload`.

## Command reference

```
tyler <command> [arguments]
```

| Command | What it does |
| --- | --- |
| `start` | Start `tylerd` in the background |
| `stop` | Stop `tylerd`; windows go back where they were |
| `restart` | Stop `tylerd` and start it again, keeping the windows in place |
| `status` | Show whether `tylerd` is running, and which build |
| `ping` | Check that `tylerd` is running |
| `list [--json]` | Show the windows `tylerd` is tracking |
| `reload` | Read the config file again and apply it |
| `focus next\|prev\|master` | Move focus within the tiling list |
| `swap next\|prev\|master` | Swap the focused window with another one |
| `layout tall\|full\|strip\|next` | Choose the layout |
| `ratio +<step>\|-<step>` | Widen or narrow the master column |
| `float toggle` | Float the focused window, or tile it again |
| `tiling on\|off\|toggle` | Start or stop tiling |
| `retile` | Put every tiled window back into its slot |
| `workspace prev\|next\|<n>` | Switch to another workspace |
| `move-to-workspace prev\|next\|<n> [--follow]` | Send the focused window to another workspace |

Commands that change windows act on the current workspace. All of them except `start`, `stop`, `restart`, `status`, `ping`, `list`, `reload` and `tiling` need tiling to be on; with tiling off they print ``tiling is off (use `tyler tiling on`)``.

### start, stop, restart

```bash
tyler start
tyler stop
tyler restart
```

`start` starts `tylerd` in the background (see [Running tylerd](#running-tylerd)) and prints its pid. If `tylerd` is already running, it says so and does nothing.

`stop` asks `tylerd` to quit, which puts every window back where it was, and waits until it has. It is not an error if `tylerd` isn't running.

`restart` stops `tylerd` and starts it again, keeping every window where it is and on its workspace (see [Running tylerd](#running-tylerd)): use it after `make build` or `make install`. A `tylerd` from before restarts kept windows can't hand them over; it is stopped normally, its windows go back where they were, and `restart` says so.

A `tylerd` started before these commands existed can't be stopped this way; `tyler` says so. Stop it once with `pkill tylerd` (or Ctrl-C), then use `tyler start`.

### status

```bash
tyler status
```

```
tylerd is running (pid 4711, up 2h 5m)
  binary  /Users/you/.local/bin/tylerd
  config  /Users/you/.config/tyler/tyler.toml
  tiling  on
```

`tiling` is `on`, `off` or `waiting for Accessibility permission`. If the `tylerd` binary has changed since it started, a warning suggests `tyler restart`. Exits with status 1 if `tylerd` isn't running.

### ping

```bash
tyler ping
```

Prints `pong` if `tylerd` is running.

### list

```bash
tyler list
tyler list --json
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
| `FLAGS` | Any of `focused`, `min` (minimized), `full` (native fullscreen), `floated` (floated with `float toggle`), `dialog`, `float` (a floating panel), `other` (a window that is never tiled) |

`--json` prints the same information as a JSON array, for scripts.

### reload

```bash
tyler reload
```

Reads the config file again and applies it. Windows on the current workspace move to their new frames at once; the other workspaces use the new settings when you switch to them. With tiling off, nothing moves until you turn it back on.

Prints `reloaded <path>`. If the file has an error, `tyler reload` prints it with its line number, exits with status 1, and the current settings stay. If there is no file, the defaults apply.

### focus

```bash
tyler focus next      # the next window in the list (wraps to the first)
tyler focus prev      # the previous window (wraps to the last)
tyler focus master    # the first window
```

Focuses a tiled window on the current workspace and brings its app to the front.

### swap

```bash
tyler swap next
tyler swap prev
tyler swap master
```

Swaps the focused window with its neighbour in the list (wrapping around) or with the master, then re-tiles. The focused window moves and keeps the focus. If the focused window already is the master, `swap master` swaps it with the second window.

### layout

```bash
tyler layout tall
tyler layout full
tyler layout strip
tyler layout next     # cycle: tall, full, strip, tall, ...
```

Sets the layout of the current workspace and prints its name.

### ratio

```bash
tyler ratio +0.05     # widen the master column
tyler ratio -0.05     # narrow it
```

Changes the master column's share of the width in the `tall` layout. The sign is required. The ratio starts at 0.5 and stays between 0.1 and 0.9; at a limit, `tyler` says so and nothing moves.

### float toggle

```bash
tyler float toggle
```

Takes the focused window out of the tiling list and leaves it where it is, or puts a floated window back into the list. Windows that are never tiled (dialogs, panels) can't be floated.

### tiling

```bash
tyler tiling on
tyler tiling off
tyler tiling toggle
```

`tiling off` stops `tylerd` from moving windows. Windows on the current workspace stay where they are, and windows parked on other workspaces come back to where they were before `tylerd` moved them. Use it when something goes wrong, or before arranging windows by hand.

`tiling on` tiles every eligible window onto the current workspace, keeping the order the list had before. Windows opened while tiling was off go to their app's assigned workspace, if it has one.

### retile

```bash
tyler retile
```

Puts every tiled window on the current workspace back into its slot, for example after an app moved or resized one of its windows itself. Windows you drag with the mouse snap back on their own (see Resizing with the mouse).

### workspace

```bash
tyler workspace next  # the next workspace (after the last comes the first)
tyler workspace prev  # the previous workspace (before the first comes the last)
tyler workspace 3     # workspace 3 (workspaces are numbered from 1)
```

Switches to another workspace. The current windows slide out and are parked, the target workspace's windows slide in, and focus goes to the window that last had focus there. On an empty workspace no window has focus (tylerd itself becomes the active app), so what you type doesn't reach a parked window. A floated window stays on screen and keeps the focus.

Focusing a parked window yourself, for example with Cmd-Tab, also switches to its workspace.

### move-to-workspace

```bash
tyler move-to-workspace next
tyler move-to-workspace 2
tyler move-to-workspace prev --follow
```

Sends the focused window to another workspace, where it becomes the focused window. Without `--follow` the window slides away towards its new workspace (to the right for `next`, to the left for `prev`), the remaining windows re-tile, and you stay on the current workspace. With `--follow` you switch to the target workspace along with the window. Sending away the last window of the current workspace leaves no window focused, as on any empty workspace.

Only tiled windows can be moved.

## Exit status and errors

| Exit status | Meaning |
| --- | --- |
| 0 | The command succeeded. Any message is printed to standard output. |
| 1 | `tylerd` refused or failed (for example `no tiled windows`), isn't running, or has no Accessibility permission. The reason is printed to standard error. |
| 2 | The command line is wrong. `tyler` prints what's wrong, followed by the usage summary. |

If some windows couldn't be moved (an app refused, or a window closed meanwhile), the command still succeeds and prints how many, for example `1 window could not be placed`.

## Environment

| Variable | Meaning |
| --- | --- |
| `TYLER_CONFIG` | Path of the config file. Default: `~/.config/tyler/tyler.toml`. |
| `TYLER_SOCKET` | Path of the socket `tyler` and `tylerd` talk over. Default: `~/.tyler/tyler.sock`. Set the same value for both to run a separate instance. `tyler start` writes the log next to it, with `.log` instead of `.sock`. |

## Example skhd bindings

skhd runs commands without your shell's `PATH`, so call `tyler` by its full path (after `make install`, `~/.local/bin/tyler`):

```
alt - j : ~/.local/bin/tyler focus next
alt - k : ~/.local/bin/tyler focus prev
alt + shift - j : ~/.local/bin/tyler swap next
alt - return : ~/.local/bin/tyler swap master
alt - h : ~/.local/bin/tyler ratio -0.05
alt - l : ~/.local/bin/tyler ratio +0.05
alt - s : ~/.local/bin/tyler workspace prev
alt - d : ~/.local/bin/tyler workspace next
alt + shift - d : ~/.local/bin/tyler move-to-workspace next
alt + ctrl + shift - d : ~/.local/bin/tyler move-to-workspace next --follow
```
