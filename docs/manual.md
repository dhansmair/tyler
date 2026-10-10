# tyler manual

tyler is a tiling window manager for macOS. It has two parts:

- **`tylerd`**, the server. It runs in the background, keeps track of your windows and moves them.
- **`tyler`**, the command-line client. Each call sends one command to `tylerd` and prints the reply.

tyler has no hotkeys of its own. To drive it from the keyboard, bind keys to `tyler` commands with a tool such as skhd, Karabiner-Elements or Raycast.

## Concepts

tyler arranges windows on displays. Each display holds a stack of workspaces, each workspace holds an ordered list of windows, and a layout turns that list into window positions.

### Display

A physical screen: the built-in screen of a laptop or an external monitor. tyler calls these *displays*. For now tyler manages only the main display (the one with the menu bar). Windows on other displays are left alone.

### Workspace

A set of windows with its own tiling list, layout and master ratio. A display has four workspaces, stacked vertically like pages and numbered 1 to 4 from the top. Exactly one workspace per display is on screen; switching to another one slides its windows into view (`tyler workspace`). Every tiled window belongs to exactly one workspace.

The windows of the workspaces that aren't on screen are *parked*: moved into the bottom-right corner of the display with only one point visible. They are still open, and Cmd-Tab still lists them. Focusing a parked window, for example with Cmd-Tab, switches to its workspace.

### Window

tyler sorts every window into one of three kinds:

- **Tiled** windows belong to a workspace and are placed by its layout. Normal app windows are tiled.
- **Floated** windows are ones you took out of tiling with `tyler float toggle`. tyler leaves them where you put them.
- **Never-tiled** windows are dialogs, sheets, panels and other special windows. tyler leaves them alone.

Floated and never-tiled windows belong to no workspace, so they stay visible whichever workspace is on screen. Minimized windows and windows in native fullscreen leave the tiling list. When they come back, they are tiled on the current workspace.

New windows are tiled on the current workspace, right after the focused window.

### Tiling list

Each workspace keeps its tiled windows in an ordered list. The first window is the *master*. A window's position in the list is its *slot* (1 is the master). Every window has a next and a previous window, and both wrap around at the ends of the list. `tyler focus` moves the focus along the list and `tyler swap` reorders it.

### Layout

A layout turns the tiling list into window frames, within the display's visible area (without the menu bar and the Dock):

- `tall`: the master fills the left column, and the other windows are stacked in the right column. Two windows sit side by side; three give one on the left and two on the right.
- `full`: every window fills the whole area.

The *master ratio* is the master column's share of the width in `tall`. Each workspace has its own layout and master ratio (`tyler layout`, `tyler ratio`).

## Running tylerd

```bash
tylerd
```

`tylerd` needs Accessibility permission. Grant it in System Settings > Privacy & Security > Accessibility to the app that starts `tylerd` (for example your terminal). Without it, `tylerd` still runs and answers `tyler ping`, and the other commands print what to do. Once you grant the permission, `tylerd` picks it up within a second; you don't have to restart it.

As soon as it has permission, `tylerd` tiles the windows on the main display, ordered left to right as they were on screen.

**Stopping.** Press Ctrl-C, or send SIGTERM (`pkill tylerd`). `tylerd` then puts every window it moved back where it was, parked windows included. A crash or `kill -9` skips this step, and windows of other workspaces stay parked in the bottom-right corner.

Only one `tylerd` can run per socket. Starting a second one fails with `already running`.

## Command reference

```
tyler <command> [arguments]
```

| Command | What it does |
| --- | --- |
| `ping` | Check that `tylerd` is running |
| `list [--json]` | Show the windows `tylerd` is tracking |
| `focus next\|prev\|master` | Move focus within the tiling list |
| `swap next\|prev\|master` | Swap the focused window with another one |
| `layout tall\|full\|next` | Choose the layout |
| `ratio +<step>\|-<step>` | Widen or narrow the master column |
| `float toggle` | Float the focused window, or tile it again |
| `tiling on\|off\|toggle` | Start or stop tiling |
| `retile` | Put every tiled window back into its slot |
| `workspace up\|down\|<n>` | Switch to another workspace |
| `move-to-workspace up\|down\|<n> [--follow]` | Send the focused window to another workspace |

Commands that change windows act on the current workspace. All of them except `ping`, `list` and `tiling` need tiling to be on; with tiling off they print ``tiling is off (use `tyler tiling on`)``.

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
| `WORKSPACE` | The workspace (1 to 4) the window is tiled on, or `-` |
| `SLOT` | The position in that workspace's tiling list (1 is the master), or `-` |
| `APP` | The application |
| `TITLE` | The window title |
| `FRAME` | Position and size, as `x,y widthxheight` in points from the top-left of the main display |
| `DISPLAY` | The physical display the window is on |
| `FLAGS` | Any of `focused`, `min` (minimized), `full` (native fullscreen), `floated` (floated with `float toggle`), `dialog`, `float` (a floating panel), `other` (a window that is never tiled) |

`--json` prints the same information as a JSON array, for scripts.

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
tyler layout next     # cycle: tall, full, tall, ...
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

`tiling on` tiles every eligible window onto the current workspace, keeping the order the list had before.

### retile

```bash
tyler retile
```

Puts every tiled window on the current workspace back into its slot. `tylerd` doesn't undo it when you drag or resize a tiled window by hand; `retile` does.

### workspace

```bash
tyler workspace down  # the next workspace (after the last comes the first)
tyler workspace up    # the previous workspace (before the first comes the last)
tyler workspace 3     # workspace 3 (workspaces are numbered 1 to 4)
```

Switches to another workspace. The current windows slide out and are parked, the target workspace's windows slide in, and focus goes to the window that last had focus there. Switching to an empty workspace doesn't change the focus.

Focusing a parked window yourself, for example with Cmd-Tab, also switches to its workspace.

### move-to-workspace

```bash
tyler move-to-workspace down
tyler move-to-workspace 2
tyler move-to-workspace up --follow
```

Sends the focused window to another workspace, where it becomes the focused window. Without `--follow` the window slides away, the remaining windows re-tile, and you stay on the current workspace. With `--follow` you switch to the target workspace along with the window.

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
| `TYLER_SOCKET` | Path of the socket `tyler` and `tylerd` talk over. Default: `~/.tyler/tyler.sock`. Set the same value for both to run a separate instance. |

## Example skhd bindings

skhd runs commands without your shell's `PATH`, so call `tyler` by its full path (after `make install`, `~/.local/bin/tyler`):

```
alt - j : ~/.local/bin/tyler focus next
alt - k : ~/.local/bin/tyler focus prev
alt + shift - j : ~/.local/bin/tyler swap next
alt - return : ~/.local/bin/tyler swap master
alt - h : ~/.local/bin/tyler ratio -0.05
alt - l : ~/.local/bin/tyler ratio +0.05
alt - s : ~/.local/bin/tyler workspace up
alt - d : ~/.local/bin/tyler workspace down
alt + shift - d : ~/.local/bin/tyler move-to-workspace down
alt + ctrl + shift - d : ~/.local/bin/tyler move-to-workspace down --follow
```
