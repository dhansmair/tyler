# mwm manual

mwm is a tiling window manager for macOS. It has two parts:

- **`mwmd`**, the server. It runs in the background, keeps track of your windows and moves them.
- **`mwm`**, the command-line client. Each call sends one command to `mwmd` and prints the reply.

mwm has no hotkeys of its own. To drive it from the keyboard, bind keys to `mwm` commands with a tool such as skhd, Karabiner-Elements or Raycast.

## Concepts

- **Tiling list.** Each virtual monitor holds an ordered list of windows. The first window is the *master*. Every window has a next and a previous window, and both wrap around at the ends of the list.
- **Layouts.** A layout turns the list into window frames:
  - `tall`: the master fills the left column, and the other windows are stacked in the right column. Two windows sit side by side; three give one on the left and two on the right.
  - `full`: every window fills the whole screen.
- **Virtual monitors.** There are four virtual monitors, stacked vertically like pages, on the main display. One is on screen at a time. The windows of the others are *parked*: moved into the bottom-right corner of the display with only one point visible. Each monitor has its own window list, layout and master ratio.
- **Floating windows.** Dialogs, sheets and windows you float with `mwm float toggle` are not tiled. They stay where they are and are visible on every monitor.
- **New windows** are tiled on the current monitor, right after the focused window.

## Running mwmd

```bash
mwmd
```

`mwmd` needs Accessibility permission. Grant it in System Settings > Privacy & Security > Accessibility to the app that starts `mwmd` (for example your terminal). Without it, `mwmd` still runs and answers `mwm ping`, and the other commands print what to do. Once you grant the permission, `mwmd` picks it up within a second; you don't have to restart it.

As soon as it has permission, `mwmd` tiles the windows on the main display, ordered left to right as they were on screen.

**Stopping.** Press Ctrl-C, or send SIGTERM (`pkill mwmd`). `mwmd` then puts every window it moved back where it was, parked windows included. A crash or `kill -9` skips this step, and windows of other monitors stay parked in the bottom-right corner.

Only one `mwmd` can run per socket. Starting a second one fails with `already running`.

## Command reference

```
mwm <command> [arguments]
```

| Command | What it does |
| --- | --- |
| `ping` | Check that `mwmd` is running |
| `list [--json]` | Show the windows `mwmd` is tracking |
| `focus next\|prev\|master` | Move focus within the tiling list |
| `swap next\|prev\|master` | Swap the focused window with another one |
| `layout tall\|full\|next` | Choose the layout |
| `ratio +<step>\|-<step>` | Widen or narrow the master column |
| `float toggle` | Float the focused window, or tile it again |
| `tiling on\|off\|toggle` | Start or stop tiling |
| `retile` | Put every tiled window back into its slot |
| `monitor up\|down\|<n>` | Switch to another virtual monitor |
| `move-to-monitor up\|down\|<n> [--follow]` | Send the focused window to another virtual monitor |

Commands that change windows act on the current monitor. All of them except `ping`, `list` and `tiling` need tiling to be on; with tiling off they print ``tiling is off (use `mwm tiling on`)``.

### ping

```bash
mwm ping
```

Prints `pong` if `mwmd` is running.

### list

```bash
mwm list
mwm list --json
```

Shows every window `mwmd` knows about, one per row:

| Column | Meaning |
| --- | --- |
| `ID` | The system's window number |
| `MONITOR` | The virtual monitor (1 to 4) the window is tiled on, or `-` |
| `SLOT` | The position in that monitor's tiling list (1 is the master), or `-` |
| `APP` | The application |
| `TITLE` | The window title |
| `FRAME` | Position and size, as `x,y widthxheight` in points from the top-left of the main display |
| `DISPLAY` | The physical display the window is on |
| `FLAGS` | Any of `focused`, `min` (minimized), `full` (native fullscreen), `floated` (floated with `float toggle`), `dialog`, `float` (a floating panel), `other` (a window that is never tiled) |

`--json` prints the same information as a JSON array, for scripts.

### focus

```bash
mwm focus next      # the next window in the list (wraps to the first)
mwm focus prev      # the previous window (wraps to the last)
mwm focus master    # the first window
```

Focuses a tiled window on the current monitor and brings its app to the front.

### swap

```bash
mwm swap next
mwm swap prev
mwm swap master
```

Swaps the focused window with its neighbour in the list (wrapping around) or with the master, then re-tiles. The focused window moves and keeps the focus. If the focused window already is the master, `swap master` swaps it with the second window.

### layout

```bash
mwm layout tall
mwm layout full
mwm layout next     # cycle: tall, full, tall, ...
```

Sets the layout of the current monitor and prints its name.

### ratio

```bash
mwm ratio +0.05     # widen the master column
mwm ratio -0.05     # narrow it
```

Changes the master column's share of the width in the `tall` layout. The sign is required. The ratio starts at 0.5 and stays between 0.1 and 0.9; at a limit, `mwm` says so and nothing moves.

### float toggle

```bash
mwm float toggle
```

Takes the focused window out of the tiling list and leaves it where it is, or puts a floated window back into the list. Windows that are never tiled (dialogs, panels) can't be floated.

### tiling

```bash
mwm tiling on
mwm tiling off
mwm tiling toggle
```

`tiling off` stops `mwmd` from moving windows. Windows on the current monitor stay where they are, and windows parked on other monitors come back to where they were before `mwmd` moved them. Use it when something goes wrong, or before arranging windows by hand.

`tiling on` tiles every eligible window onto the current monitor, keeping the order the list had before.

### retile

```bash
mwm retile
```

Puts every tiled window on the current monitor back into its slot. `mwmd` doesn't undo it when you drag or resize a tiled window by hand; `retile` does.

### monitor

```bash
mwm monitor down    # the next monitor (after the last comes the first)
mwm monitor up      # the previous monitor (before the first comes the last)
mwm monitor 3       # monitor 3 (monitors are numbered 1 to 4)
```

Switches to another virtual monitor. The current windows slide out and are parked, the target monitor's windows slide in, and focus goes to the window that last had focus there. Switching to an empty monitor doesn't change the focus.

Focusing a parked window yourself, for example with Cmd-Tab, also switches to its monitor.

### move-to-monitor

```bash
mwm move-to-monitor down
mwm move-to-monitor 2
mwm move-to-monitor up --follow
```

Sends the focused window to another monitor, where it becomes the focused window. Without `--follow` the window slides away, the remaining windows re-tile, and you stay on the current monitor. With `--follow` you switch to the target monitor along with the window.

Only tiled windows can be moved.

## Exit status and errors

| Exit status | Meaning |
| --- | --- |
| 0 | The command succeeded. Any message is printed to standard output. |
| 1 | `mwmd` refused or failed (for example `no tiled windows`), isn't running, or has no Accessibility permission. The reason is printed to standard error. |
| 2 | The command line is wrong. `mwm` prints what's wrong, followed by the usage summary. |

If some windows couldn't be moved (an app refused, or a window closed meanwhile), the command still succeeds and prints how many, for example `1 window could not be placed`.

## Environment

| Variable | Meaning |
| --- | --- |
| `MWM_SOCKET` | Path of the socket `mwm` and `mwmd` talk over. Default: `~/.mwm/mwm.sock`. Set the same value for both to run a separate instance. |

## Example skhd bindings

skhd runs commands without your shell's `PATH`, so call `mwm` by its full path (after `make install`, `~/.local/bin/mwm`):

```
alt - j : ~/.local/bin/mwm focus next
alt - k : ~/.local/bin/mwm focus prev
alt + shift - j : ~/.local/bin/mwm swap next
alt - return : ~/.local/bin/mwm swap master
alt - h : ~/.local/bin/mwm ratio -0.05
alt - l : ~/.local/bin/mwm ratio +0.05
alt - s : ~/.local/bin/mwm monitor up
alt - d : ~/.local/bin/mwm monitor down
alt + shift - d : ~/.local/bin/mwm move-to-monitor down
alt + ctrl + shift - d : ~/.local/bin/mwm move-to-monitor down --follow
```
